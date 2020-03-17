#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>
#include <string.h>
#include <gelf.h>
#include <libelf.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <assert.h>
#include <stdlib.h>
#include <iostream>
#include <arpa/inet.h>
#include <ncurses.h>
#include <set>
#include "system.h"
#include "Vtop.h"

#define STACK_PAGES     (100)

using namespace std;

System* System::sys;

System::System(Vtop* top, uint64_t ramsize, const char* binaryfn, const int argc, char* argv[], int ps_per_clock)
    : top(top), ps_per_clock(ps_per_clock), ramsize(ramsize), dram_offset(0), max_elf_addr(0), show_console(false), interrupts(0), w_count(0), ticks(0), ecall_brk(0), errno_addr(NULL)
{
    sys = this;

    char* HAVETLB = getenv("HAVETLB");
    use_virtual_memory = HAVETLB && (toupper(*HAVETLB) == 'Y');

    char* FULLSYSTEM = getenv("FULLSYSTEM");
    full_system = FULLSYSTEM && (toupper(*FULLSYSTEM) == 'Y');

    assert(!full_system || !use_virtual_memory);

    string ram_fn = string("/vtop-system-")+to_string(getpid());
    ram_fd = shm_open(ram_fn.c_str(), O_RDWR|O_CREAT|O_EXCL, 0600);
    assert(ram_fd != -1);
    assert(shm_unlink(ram_fn.c_str()) == 0);
    assert(ftruncate(ram_fd, ramsize) == 0);
    ram = (char*)mmap(NULL, ramsize, PROT_READ|PROT_WRITE, MAP_SHARED, ram_fd, 0);
    assert(ram != MAP_FAILED);
    if (use_virtual_memory) {
      ram_virt = (char*)mmap(NULL, ramsize, PROT_NONE, MAP_ANONYMOUS|MAP_PRIVATE, -1, 0);
      assert(ram_virt != MAP_FAILED);
    } else if (full_system) {
      dram_offset = -DRAM_OFFSET;
    }

    // load the program image
    if (binaryfn) top->entry = load_binary(binaryfn);

    if (!full_system) {
      ecall_brk = max_elf_addr;

      top->satp = get_phys_page() << 12;
      top->stackptr = ramsize - 4*MEGA;
      for(int n = 1; n < STACK_PAGES; ++n) virt_to_phy(top->stackptr - PAGE_SIZE*n); // allocate stack pages

      uint64_t* argvp = (uint64_t*)(ram+virt_to_phy(top->stackptr));
      argvp[0] = argc;
      uint64_t dst = top->stackptr + 8/*argc*/ + 8*argc + 8/*envp*/ + 8/*env*/;
      argvp[argc+1] = dst-8; // envp
      argvp[argc+2] = 0; // env array
      for(int arg = 0; arg < argc; ++arg) {
          argvp[arg+1] = dst;
          char* src = argv[arg];
          do {
              virt_to_phy(dst); // make sure phys page is allocated
              ram_virt[dst] = *src;
              dst++;
          } while(*(src++));
      }
      virt_to_phy(0); // TODO: must initialize auxv vector with AT_RANDOM value.  until then, _dl_random will be a null pointer, so need to prefault address 0
    }

    // create the dram simulator
    dramsim = DRAMSim::getMemorySystemInstance("DDR2_micron_16M_8b_x8_sg3E.ini", "system.ini", "../dramsim2", "dram_result", ramsize / MEGA);
    DRAMSim::TransactionCompleteCB *read_cb = new DRAMSim::Callback<System, void, unsigned, uint64_t, uint64_t>(this, &System::dram_read_complete);
    DRAMSim::TransactionCompleteCB *write_cb = new DRAMSim::Callback<System, void, unsigned, uint64_t, uint64_t>(this, &System::dram_write_complete);
    dramsim->RegisterCallbacks(read_cb, write_cb, NULL);
    dramsim->setCPUClockSpeed(1000ULL*1000*1000*1000/ps_per_clock);
}

System::~System() {
    assert(munmap(ram, ramsize) == 0);
    assert(!use_virtual_memory || munmap(ram_virt, ramsize) == 0);
    assert(close(ram_fd) == 0);

    if (show_console) {
        sleep(2);
        endwin();
    }
}

void System::console() {
    show_console = true;
    if (show_console) {
        initscr();
        start_color();
        noecho();
        cbreak();
        timeout(0);
    }
}

void System::tick(int clk) {

    if (top->reset) {
        if (top->m_axi_arvalid || top->m_axi_awvalid)
            cerr << "Received a bus request during RESET.  Ignoring..." << endl;
        top->m_axi_awready = top->m_axi_wready = top->m_axi_arready = 1;
        addr_to_tag.clear();
        r_queue.clear();
        resp_queue.clear();
        snoop_queue.clear();
        return;
    }

    if (!clk) {
        if (top->m_axi_rvalid && top->m_axi_rready) r_queue.pop_front();
        if (top->m_axi_bvalid && top->m_axi_bready) resp_queue.pop_front();
        if (top->m_axi_acvalid && top->m_axi_acready) snoop_queue.erase(snoop_queue.begin());
        return;
    }

    dramsim->update();    

    if (top->m_axi_arvalid) {
        uint64_t xfer_addr = top->m_axi_araddr & ~0x3fULL;
        if (top->m_axi_arburst != 2) {
            cerr << "Read request with non-wrap burst (" << std::dec << top->m_axi_arburst << ") unsupported" << endl;
            Verilated::gotFinish(true);
        } else if (top->m_axi_arlen+1 != 8) {
              cerr << "Read request with length != 8 (" << std::dec << top->m_axi_arlen << "+1)" << endl;
              Verilated::gotFinish(true);
        } else if (xfer_addr > (dram_offset + ramsize - 64)) {
            cerr << "Invalid 64-byte access, address " << std::hex << xfer_addr << " is beyond end of memory at " << ramsize << endl;
            Verilated::gotFinish(true);
        } else if (addr_to_tag.find(xfer_addr)!=addr_to_tag.end()) {
            cerr << "Access for " << std::hex << xfer_addr << " already outstanding.  Ignoring..." << endl;
        } else {
            assert(willAcceptTransaction(xfer_addr)); // if this gets triggered, need to rethink AXI "ready" signal strategy
            assert(
                    dramsim->addTransaction(false, xfer_addr)
                  );
            addr_to_tag[xfer_addr] = make_pair(top->m_axi_araddr, top->m_axi_arid);
        }
    }

    top->m_axi_rvalid = 0;
    if (!r_queue.empty()) {
        top->m_axi_rvalid = 1;
        top->m_axi_rdata = r_queue.begin()->first;
        top->m_axi_rid = r_queue.begin()->second.first;
        top->m_axi_rlast = r_queue.begin()->second.second;
    }

    if (top->m_axi_awvalid) {
        w_addr = top->m_axi_awaddr & ~0x3fULL;

        if (top->m_axi_awburst != 1) {
            cerr << "Write request with non-incr burst (" << std::dec << top->m_axi_awburst << ") unsupported" << endl;
            Verilated::gotFinish(true);
        } else if (top->m_axi_awlen+1 != 8) {
            cerr << "Write request with length != 8 (" << std::dec << top->m_axi_awlen << "+1)" << endl;
            Verilated::gotFinish(true);
        } else if (w_addr > (dram_offset + ramsize - 64)) {
            cerr << "Invalid 64-byte access, address " << std::hex << w_addr << " is beyond end of memory at " << ramsize << endl;
            Verilated::gotFinish(true);
        } else if (addr_to_tag.find(w_addr)!=addr_to_tag.end()) {
            cerr << "Access for " << std::hex << w_addr << " already outstanding.  Ignoring..." << endl;
        } else {
            assert(willAcceptTransaction(w_addr)); // if this gets triggered, need to rethink AXI "ready" signal strategy
            assert(
                    dramsim->addTransaction(true, w_addr)
                  );
            addr_to_tag[w_addr] = make_pair(top->m_axi_awaddr, top->m_axi_awid);
        }
        w_count = 8;
    }

    if (top->m_axi_wvalid && w_count) {
        // if transfer is in progress, can't change mind about willAcceptTransaction()
        assert(willAcceptTransaction(w_addr));
        *((uint64_t*)(&ram[dram_offset + w_addr + (8-w_count)*8])) = top->m_axi_wdata;
        if(--w_count == 0) assert(top->m_axi_wlast);
    }

    top->m_axi_bvalid = 0;
    if (!resp_queue.empty()) {
        top->m_axi_bvalid = 1;
        top->m_axi_bid = *resp_queue.begin();
    }

    top->m_axi_acvalid = 0;
    if (!snoop_queue.empty()) {
        top->m_axi_acvalid = 1;
        top->m_axi_acaddr = *snoop_queue.begin();
        top->m_axi_acsnoop = 0xD; // MakeInvalid
    }
}

void System::dram_read_complete(unsigned id, uint64_t address, uint64_t clock_cycle) {
    map<uint64_t, pair<uint64_t, int> >::iterator tag = addr_to_tag.find(address);
    assert(tag != addr_to_tag.end());
    uint64_t orig_addr = tag->second.first;
    for(int i = 0; i < 64; i += 8)
        r_queue.push_back(make_pair(*((uint64_t*)(&ram[dram_offset + ((orig_addr&(~63))+((orig_addr+i)&63))])),make_pair(tag->second.second,i+8>=64)));
    addr_to_tag.erase(tag);
}

void System::dram_write_complete(unsigned id, uint64_t address, uint64_t clock_cycle) {
    do_finish_write(address, 64);
    map<uint64_t, pair<uint64_t, int> >::iterator tag = addr_to_tag.find(address);
    assert(tag != addr_to_tag.end());
    resp_queue.push_back(tag->second.second);
    addr_to_tag.erase(tag);
}

void System::set_errno(const int new_errno) {
    if (errno_addr) {
        *errno_addr = new_errno;
        invalidate((char*)errno_addr - ram);
    }
}

void System::invalidate(const uint64_t phy_addr) {
    snoop_queue.insert(phy_addr & ~0x3fULL);
}

uint64_t System::get_phys_page() {
    int page_no;
    do {
        page_no = rand()%(ramsize/PAGE_SIZE);
    } while(phys_page_used[page_no]);
    phys_page_used[page_no] = true;
    return page_no;
}

#define VM_DEBUG 0

uint64_t System::get_pte(uint64_t base_addr, int vpn, bool isleaf, bool& allocated) {
    uint64_t addr = base_addr + vpn*8;
    uint64_t pte = *(uint64_t*) & ram[addr];
    uint64_t page_no = pte >> 10;
    if(!(pte & VALID_PAGE)) {
        page_no = get_phys_page();
        if (isleaf)
            (*(uint64_t*)&ram[addr]) = (page_no<<10) | VALID_PAGE;
        else
            (*(uint64_t*)&ram[addr]) = (page_no<<10) | VALID_PAGE_DIR;
        pte = *(uint64_t*) & ram[addr];
        if (VM_DEBUG) {
            cout << "Addr:" << std::dec << addr << endl;
            cout << "Initialized page no " << std::dec << page_no << endl;
        }
        allocated = isleaf;
    } else {
        allocated = false;
    }
    assert(page_no < ramsize/PAGE_SIZE);
    return pte;
}

uint64_t System::virt_to_phy(const uint64_t virt_addr) {

    if (!use_virtual_memory) {
      if (virt_addr >= ramsize) {
          cerr << "Invalid virt_to_phy, address " << std::hex << virt_addr << " is beyond end of memory at " << ramsize << endl;
          Verilated::gotFinish(true);
          return 0; // return fake translation to avoid core dump from bad address on the last cycle
      }
      return virt_addr;
    }

    bool allocated;
    uint64_t pt_base_addr = top->satp;
    uint64_t phy_offset = virt_addr & (PAGE_SIZE-1);
    uint64_t tmp_virt_addr = virt_addr >> 12;
    for(int i = 0; i < 4; i++) {
        int vpn = (tmp_virt_addr & (0x01ff << 9*(3-i))) >> 9*(3-i);
        uint64_t pte = get_pte(pt_base_addr, vpn, i == 3, allocated);
        pt_base_addr = ((pte&0x0000ffffffffffff)>>10)<<12;
    }
    if (allocated) {
        void* new_virt = ram_virt + (virt_addr & ~(PAGE_SIZE-1));
        assert(mmap(new_virt, PAGE_SIZE, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_FIXED, ram_fd, pt_base_addr) == new_virt);
    }
    assert((pt_base_addr | phy_offset) < ramsize);
    return (pt_base_addr | phy_offset);
}

void System::load_segment(const int fd, const size_t memsz, const size_t filesz, uint64_t virt_addr) {
    if (VM_DEBUG) cout << "Read " << std::dec << filesz << " bytes at " << std::hex << virt_addr << endl;
    for(size_t i = 0; i < memsz; ++i) assert(virt_to_phy(virt_addr + i)); // prefault
    assert(filesz == read(fd, &ram_virt[virt_addr], filesz));
}

uint64_t System::load_binary(const char* filename) {

    // open the elf file
    int fd = open(filename, O_RDONLY);
    assert(fd != -1);

    if (full_system) {
      off_t sz = lseek(fd, 0L, SEEK_END);
      assert(sz == pread(fd, &ram[0], sz, 0));
      close(fd);
      return 0x80000000ULL;
    }

    // check libelf version
    if (elf_version(EV_CURRENT) == EV_NONE) {
        cerr << "ELF binary out of date" << endl;
        exit(-1);
    }

    // start reading the file
    Elf* elf = elf_begin(fd, ELF_C_READ, NULL);
    if (NULL == elf) {
        cerr << "Could not initialize the ELF data structures" << endl;
        exit(-1);
    }

    if (elf_kind(elf) != ELF_K_ELF) {
        cerr << "Not an ELF object: " << filename << endl;
        exit(-1);
    }

    GElf_Ehdr elf_header;
    gelf_getehdr(elf, &elf_header);

    if (!elf_header.e_phnum) { // loading simple object file
        Elf_Scn* scn = NULL;
        while((scn = elf_nextscn(elf, scn)) != NULL) {
            GElf_Shdr shdr;
            gelf_getshdr(scn, &shdr);
            if (shdr.sh_type != SHT_PROGBITS) continue;
            if (!(shdr.sh_flags & SHF_EXECINSTR)) continue;

            // copy segment content from file to memory
            assert(-1 != lseek(fd, shdr.sh_offset, SEEK_SET));
            load_segment(fd, shdr.sh_size, shdr.sh_size, 0);
            break; // just load the first one
        }
    } else {
        for(unsigned phn = 0; phn < elf_header.e_phnum; phn++) {
            GElf_Phdr phdr;
            gelf_getphdr(elf, phn, &phdr);

            switch(phdr.p_type) {
            case PT_LOAD: {
                if ((phdr.p_vaddr + phdr.p_memsz) > ramsize) {
                    cerr << "Not enough 'physical' ram" << endl;
                    exit(-1);
                }
                cout << "Loading ELF header #" << phn << "."
                    << " offset: "   << phdr.p_offset
                    << " filesize: " << phdr.p_filesz
                    << " memsize: "  << phdr.p_memsz
                    << " vaddr: "    << std::hex << phdr.p_vaddr << std::dec
                    << " paddr: "    << std::hex << phdr.p_paddr << std::dec
                    << " align: "    << phdr.p_align
                    << endl;

                // copy segment content from file to memory
                assert(-1 != lseek(fd, phdr.p_offset, SEEK_SET));
                load_segment(fd, phdr.p_memsz, phdr.p_filesz, phdr.p_vaddr);

                if (max_elf_addr < (phdr.p_vaddr + phdr.p_memsz))
                    max_elf_addr = (phdr.p_vaddr + phdr.p_memsz);
                break;
            }
            case PT_TLS:
                errno_addr = (int*)(ram + phdr.p_vaddr + 0x20 /* errno, grep ".*TLS.* errno$" */);
                cout << "Setting errno_addr to " << std::hex << errno_addr << " (TLS at " << phdr.p_vaddr << "+0x20)" << endl;
                break;
            case PT_DYNAMIC:
            case PT_NOTE:
            case PT_GNU_STACK:
            case PT_GNU_RELRO:
                // do nothing
                break;
            default:
                cerr << "Unexpected ELF header " << phdr.p_type << endl;
                exit(-1);
            }
        }

        // page-align max_elf_addr
        max_elf_addr = ((max_elf_addr + PAGE_SIZE-1) / PAGE_SIZE) * PAGE_SIZE;
    }
    // finalize
    close(fd);
    return elf_header.e_entry /* entry point */;
}

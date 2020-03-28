#ifndef __SYSTEM_H
#define __SYSTEM_H

#include <map>
#include <list>
#include <set>
#include <queue>
#include <utility>
#include <bitset>
#include "DRAMSim2/DRAMSim.h"
#include "Vtop.h"

#define KILO (1024UL)
#define MEGA (1024UL*1024)
#define GIGA (1024UL*1024*1024)

#define PAGE_SIZE       (4096UL)
#define VALID_PAGE_DIR  (0b0000000001) //RISCV nonleaf pages must be rwx=0, v=1
#define VALID_PAGE      (0b0000001111) // This is a rwx leaf (for now). Later will be more specific about perms

typedef unsigned long __uint64_t;
typedef __uint64_t uint64_t;
typedef unsigned int __uint32_t;
typedef __uint32_t uint32_t;
typedef int __int32_t;
typedef __int32_t int32_t;
typedef unsigned short __uint16_t;
typedef __uint16_t uint16_t;

class System {
    Vtop* top;

    enum { IRQ_TIMER=0, IRQ_KBD=1 };
    int interrupts;
    std::queue<char> keys;
    int* errno_addr;

    bool show_console;

    uint64_t load_elf(const char* filename);

    list<pair<uint64_t, pair<int, bool> > > r_queue;
    list<int> resp_queue;
    set<uint64_t> snoop_queue;
    uint64_t w_addr;
    int w_count;
    std::map<uint64_t, std::pair<uint64_t, int> > addr_to_tag;

    void dram_read_complete(unsigned id, uint64_t address, uint64_t clock_cycle);
    void dram_write_complete(unsigned id, uint64_t address, uint64_t clock_cycle);

    bitset<GIGA/PAGE_SIZE> phys_page_used;
    bool use_virtual_memory;
    uint64_t get_phys_page();
    uint64_t get_pte(uint64_t base_addr, int vpn, bool isleaf, bool& allocated);
    uint64_t load_elf_parts(int fileDescriptor, size_t size, const uint64_t virt_addr);
    void load_segment(const int fd, const size_t memsz, const size_t filesz, uint64_t virt_addr);

    DRAMSim::MultiChannelMemorySystem* dramsim;
    bool willAcceptTransaction(uint64_t addr) {
      // hack: false if /any/ memory channel can't accept transaction
      return dramsim->willAcceptTransaction();
    }
    
public:
    static System* sys;
    uint64_t max_elf_addr;
    uint64_t ecall_brk;

    uint64_t ticks;
    int ps_per_clock;

    void set_errno(const int new_errno);
    void invalidate(const uint64_t phys_addr);
    uint64_t virt_to_phy(const uint64_t virt_addr);

    char* ram;
    unsigned int ramsize;
    char* ram_virt;
    int ram_fd;

    System(Vtop* top, unsigned ramsize, const char* ramelf, const int argc, char* argv[], int ps_per_clock);
    ~System();

    void console();
    void tick(int clk);
};

#endif

#include <iostream>
#include "system.h"
#include "hardware.h"

using namespace std;

static uint64_t ticks_to_timer = 0;
void rtc_tick(Vtop* top) {
    if (ticks_to_timer == 1) top->hz32768timer = 1;
    else if (ticks_to_timer == 0) {
        top->hz32768timer = 1;
        ticks_to_timer = 1000000000000ULL/32768/System::sys->ps_per_clock;
    }
    --ticks_to_timer;
}

void write_one(const Device* self, Vtop* top) {
    System::sys->w_addr = top->m_axi_awaddr;
    System::sys->w_count = 1;
}

void clint_read(const Device* self, Vtop* top) {
    //cerr << "Read request of CLINT address (" << std::hex << System::sys->w_addr << ") unsupported, but will return 0 and keep going" << endl;
    System::sys->read_response(0, top->m_axi_arid, true);
}

void clint_write_data(const Device* self, Vtop* top) {
    //cerr << "Write request of CLINT address (" << std::hex << System::sys->w_addr << ") unsupported, but will keep going anyway" << endl;
}

enum { UART_LITE_REG_RXFIFO = 0, UART_LITE_REG_TXFIFO = 1, UART_LITE_STAT_REG = 2, UART_LITE_CTRL_REG = 3 };
enum { UART_LITE_TX_FULL = 3, UART_LITE_RX_FULL = 1, UART_LITE_RX_VALID = 0 };

void uart_lite_read(const Device* self, Vtop* top) {
    int offset = (top->m_axi_araddr - self->start)/4;
    switch(offset) {
        case UART_LITE_STAT_REG:
            System::sys->read_response(0, top->m_axi_arid, true);
            break;
        default:
            cerr << "Read request of uart_lite address (" << std::hex << top->m_axi_araddr << "/" << offset << ") unsupported" << endl;
            Verilated::gotFinish(true);
            break;
    }
}

void uart_lite_write_data(const Device* self, Vtop* top) {
    int offset = (System::sys->w_addr - self->start)/4;
    if (top->m_axi_wstrb != 0x0F)  {
        cerr << "Write request with unsupported strobe value (" << std::hex << (int)(top->m_axi_wstrb) << ")" << endl;
        Verilated::gotFinish(true);
    }
    switch(offset) {
        case UART_LITE_REG_TXFIFO:
            cout << (char)(top->m_axi_wdata) << std::flush;
            break;
        case UART_LITE_CTRL_REG:
            // do nothing
            break;
        default:
            cerr << "Write request of uart_lite address (" << std::hex << System::sys->w_addr << "/" << offset << ") unsupported" << endl;
            Verilated::gotFinish(true);
            break;
    }
}

const struct Device devices[] = {
    { 0x70aeef00ULL, 0x000c0000, clint_read, write_one, clint_write_data },
    { 0x70beef00ULL, 0x00010000, uart_lite_read, write_one, uart_lite_write_data }
};

const Device* full_system_hardware_match(const uint64_t addr) {
    for(const Device* d = devices; d < devices+sizeof(devices)/sizeof(Device); ++d)
        if (d->start <= addr && addr < d->start + d->size) return d;
    return NULL;
}

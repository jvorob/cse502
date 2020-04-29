#ifndef __HARDWARE_H
#define __HARDWARE_H

#include "Vtop.h"

void rtc_tick(Vtop* top);

struct Device {
  uint64_t start, size;
  void (*read)(const Device* self, Vtop* top);
  void (*write_addr)(const Device* self, Vtop* top);
  void (*write_data)(const Device* self, Vtop* top);
};
const Device* full_system_hardware_match(const uint64_t addr);

#endif

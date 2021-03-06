/*
 * Copyright (c) 2016 Eric B. Decker
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 *
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 *
 * - Neither the name of the copyright holders nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL
 * THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/**
 * @author Eric B. Decker <cire831@gmail.com>
 */

#include "hardware.h"

module Si446xPinsP {
  provides {
    interface Si446xInterface as HW;
  }
  uses {
    interface GpioInterrupt  as RadioNIRQ;
  }
}
implementation {
  async command uint8_t HW.si446x_cts()             { return SI446X_CTS_P; }
  async command uint8_t HW.si446x_irqn()            { return SI446X_IRQN_P; }
  async command uint8_t HW.si446x_sdn()             { return SI446X_SDN_IN; }
  async command uint8_t HW.si446x_csn()             { return SI446X_CSN_IN; }
  async command void    HW.si446x_shutdown()        { SI446X_SDN = 1; }
  async command void    HW.si446x_unshutdown()      { SI446X_SDN = 0; }
  async command void    HW.si446x_set_cs()          { SI446X_CSN = 0; }
  async command void    HW.si446x_clr_cs()          { SI446X_CSN = 1; }
  async command void    HW.si446x_set_low_tx_pwr()  { SI446X_VOLT_SEL = 0; }
  async command void    HW.si446x_set_high_tx_pwr() { SI446X_VOLT_SEL = 1; }

  async command void    HW.si446x_enableInterrupt() {
    atomic {
      call RadioNIRQ.enableFallingEdge();
    }
  }

  async command void    HW.si446x_disableInterrupt() {
    atomic {
      call RadioNIRQ.disable();
    }
  }

  async event void RadioNIRQ.fired() {
    signal HW.si446x_interrupt();
  }
}

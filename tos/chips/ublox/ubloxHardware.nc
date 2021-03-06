/*
 * Copyright (c) 2020, Eric B. Decker
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 * See COPYING in the top level directory of this source tree.
 *
 * Contact: Eric B. Decker <cire831@gmail.com>
 */

/**
 * Define the interface to uBlox GPS chips using Port Abstractionish.
 *
 * Following pins can be manipulated:
 *
 *  gps_csn():            (set/clr) chip select.
 *  gps_reset():          (set/clr) access to reset pin.
 *
 *  gps_pwr_on():         turn pwr on (really?)
 *  gps_pwr_off():        your guess here.
 *  gps_powered():        return true if gps is powered (h/w power).
 *
 * data transfer
 *
 *  spi_put():            splitWrite()     w timeout
 *  spi_get():            splitRead()      w timeout
 *  spi_getput():         splitReadWrite() w timeout
 *
 *  gps_txrdy():             returns state of txrdy pin
 *  gps_txrdy_int_enabled(): returns state of txrdy interrupt
 *  gps_txrdy_int_enable():  enable/disable txrdy interrupt.
 *  gps_txrdy_int_disable():
 *
 *  gps_send_block():     transmit a block of data.
 *  gps_send_block_done():
 *  gps_byte_avail():     from h/w driver to gps driver.
 *
 * @author Eric B. Decker <cire831@gmail.com>
 *
 *  gps_rx_err():         report rx errors
 *  gps_clear_rx_errs():  clear rx_errs cells.
 */

interface ubloxHardware {

  command void gps_set_cs();
  command void gps_clr_cs();

  command void gps_set_reset();
  command void gps_clr_reset();

  command bool gps_powered();
  command void gps_pwr_on();
  command void gps_pwr_off();

  command void    spi_put(uint8_t byte);
  command uint8_t spi_get();
  command uint8_t spi_getput(uint8_t byte);

  command bool gps_txrdy();
  command bool gps_txrdy_int_enabled();
  command void gps_txrdy_int_enable();
  command void gps_txrdy_int_disable();

  /*
   * Data transfer
   */
  command void gps_send(uint8_t *ptr, uint16_t len);
  event   void gps_send_done(error_t err);
  event   void gps_byte_avail(uint8_t byte);
}

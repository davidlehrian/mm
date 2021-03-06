/**
 * Copyright (c) 2017-2019, Eric Decker, Dan Maltbie
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
 *          Daniel J. Maltbie <dmaltbie@daloma.com>
 */

interface DblkManager {
  /* return start of the DBLK file, abs sector blk_id */
  async command uint32_t get_dblk_low();

  /* return end (inclusive) of the DBLK file, abs sector blk_id */
  async command uint32_t get_dblk_high();

  /* return the next abs blk_id that will be written next */
  async command uint32_t get_dblk_nxt();

  /*
   * return current file relative offset of dblk_nxt (from dblk_low)
   * this is the file offset of the next block to be written.
   */
  async command uint32_t dblk_nxt_offset();

  /* advance dblk_nxt and return the new value */
  async command uint32_t adv_dblk_nxt();

  /* return current record number */
  async command uint32_t cur_recnum();

  /* advance cur_recnum and return the new value */
  async command uint32_t adv_cur_recnum();

  /* return recnum of 1st record written after boot, SYNC/R */
  async command uint32_t boot_recnum();

  /* return offset of 1st record written after boot, SYNC/R */
  async command uint32_t boot_offset();

  /**
   * validate a contiguous header
   *
   * verify the hdr's crc8.  If the crc8 is good, we assume the
   * header is valid.  Seems reasonable.
   */
  async command bool hdrValid(dt_header_t *header);
}

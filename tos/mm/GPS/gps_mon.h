/*
 * Copyright (c) 2017-2018 Eric B. Decker
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

/*
 * gps_mon.h: definitions for GPSmonitor state and commands.
 */

#ifndef __GPS_MON_H__
#define __GPS_MON_H__

#ifndef PACKED
#define PACKED __attribute__((__packed__))
#endif

typedef enum gps_debug_cmds {
  GDC_NOP           = 0,
  GDC_TURNON        = 1,
  GDC_TURNOFF       = 2,
  GDC_STANDBY       = 3,
  GDC_POWER_ON      = 4,
  GDC_POWER_OFF     = 5,
  GDC_CYCLE         = 6,

  GDC_AWAKE_STATUS  = 0x10,
  GDC_MPM           = 0x11,
  GDC_PULSE         = 0x12,
  GDC_RESET         = 0x13,
  GDC_RAW_TX        = 0x14,
  GDC_HIBERNATE     = 0x15,
  GDC_WAKE          = 0x16,

  /*
   * canned messages are in the array canned_msgs
   * indexed by gp->data[0], 1st byte following the
   * cmd.
   */
  GDC_CANNED        = 0x80,

  GDC_LOW           = 0xfc,
  GDC_SLEEP         = 0xfd,
  GDC_PANIC         = 0xfe,
  GDC_REBOOT        = 0xff,
} gps_cmd_t;


/*
 * gps_cmd packets come across TagNet and there are no alignment
 * constraints.  they simply are bytes.  Multibyte datums must be repacked
 * before used natively.
 */
typedef struct {
  uint8_t cmd;
} PACKED gps_simple_cmd_t;


typedef struct {
  uint8_t cmd;
  uint8_t data[];
} PACKED gps_raw_tx_t;


typedef enum mon_events {
  MON_EV_NONE       = 0,
  MON_EV_BOOT       = 1,
  MON_EV_STARTUP    = 2,
  MON_EV_FAIL       = 3,
  MON_EV_TIMEOUT    = 4,
  MON_EV_SWVER      = 5,
  MON_EV_MSG        = 6,
  MON_EV_OTS_NO     = 7,
  MON_EV_OTS_YES    = 8,
  MON_EV_LOCK_POS   = 9,
  MON_EV_LOCK_TIME  = 10,
  MON_EV_MPM        = 11,
  MON_EV_MPM_ERROR  = 12,
} mon_event_t;


typedef enum {
  GMS_OFF           = 0,                /* fresh boot */
  GMS_FAIL          = 1,                /* down, couldn't make it work */
  GMS_BOOTING       = 2,                /* letting driver communicate  */
  GMS_STARTUP       = 3,                /* config and inital swver */

  GMS_COMM_CHECK    = 4,                /* can we hear? */
  GMS_LOCK_SEARCH   = 5,                /* looking for lock */

  GMS_MPM_WAIT      = 6,                /* trying to go into MPM */
  GMS_MPM_RESTART   = 7,                /* mpm recovery, wait for shutdown */
  GMS_MPM           = 8,                /* in MPM */

  GMS_COLLECT       = 9,                /* gathering fixes */

  GMS_STANDBY       = 10,               /* currently not used */
  GMS_UP            = 11,               /* currently not used */
  GMS_MAX           = 11,

} gpsm_state_t;                         /* gps monitor state */


typedef enum {
  GMS_MAJOR_NONE           = 0,         /* fresh boot */
  GMS_MAJOR_CYCLE          = 1,         /* lock cycle */
  GMS_MAJOR_MPM_COLLECT    = 2,         /* MPM Collection  */
  GMS_MAJOR_SATS_COLLECT   = 3,         /* SATS Collection */
  GMS_MAJOR_TIME_COLLECT   = 4,         /* TIME sync Collection    */
  GMS_MAJOR_MAX            = 4,
} gpsm_major_state_t;                   /* gps monitor major state */


#endif  /* __GPS_MON_H__ */

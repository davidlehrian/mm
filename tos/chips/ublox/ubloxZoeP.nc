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
 *          Daniel J. Maltbie <dmaltbie@daloma.org>
 *
 * Dedicated usci spi port.
 */

#include <panic.h>
#include <platform_panic.h>
#include <gps_ublox.h>
#include <ublox_driver.h>
#include <typed_data.h>
#include <overwatch.h>

#ifndef PANIC_GPS
enum {
  __pcode_gps = unique(UQ_PANIC_SUBSYS)
};

#define PANIC_GPS __pcode_gps
#endif

typedef enum {
  GPSC_OFF              = 0,            /* pwr is off */

  GPSC_ON               = 1,            // at msg boundary
  GPSC_ON_RX            = 2,            // in process of receiving a packet, timer on
  GPSC_ON_TX            = 3,            // doing transmit, txtimer running.
  GPSC_ON_RX_TX         = 4,            // not really used.  TX atomic

  GPSC_CONFIG_BOOT      = 5,            /* bootstrap initilization */
  GPSC_CONFIG_CHK       = 6,            /* configuration check     */
  GPSC_CONFIG_SET_TXRDY = 7,            /* need txrdy configured   */
  GPSC_CONFIG_TXRDY_ACK = 8,            /* waiting for ack         */
  GPSC_CONFIG_DONE      = 9,            /* good to go */
  GPSC_VER_WAIT         = 10,           /* waiting for ver string  */
  GPSC_VER_DONE         = 11,           /* found it. */

  GPSC_PWR_UP_WAIT      = 12,           /* waiting for power up    */

  GPSC_HIBERNATE        = 13,           // place holder

  GPSC_RESET_WAIT       = 14,           /* reset dwell */

  GPSC_FAIL             = 15,

} gpsc_state_t;                         // gps control state


typedef enum {
  GPSW_NONE = 0,
  GPSW_BOOT,
  GPSW_TURNON,
  GPSW_TURNOFF,
  GPSW_STANDBY,
  GPSW_TX_TIMER,
  GPSW_RX_TIMER,
  GPSW_PROTO_START,
  GPSW_PROTO_ABORT,
  GPSW_PROTO_END,
  GPSW_TX_SEND,
} gps_where_t;


typedef enum {
  GPSE_NONE = 0,
  GPSE_STATE,                           /* state change */
  GPSE_CONFIG,                          /* config message sent */
  GPSE_CONFIG_ACK,                      /* config message acked */
  GPSE_ABORT,                           /* protocol abort */
  GPSE_TX_POST,                         /* tx h/w int posted */
  GPSE_TIMEOUT,                         /* timeout */
} gps_event_t;


enum {
  /* default tx deadman */
  GPS_TX_WAIT_DEFAULT = 2048,

  /* delay between config messages */
  GPS_TX_CONFIG_DELAY = 256,
};


/*
 * gpsc_state:  current state of the driver state machine
 * gpsc_in_msg: true if within message boundaries.
 */
norace gpsc_state_t	    gpsc_state;
norace bool                 gpsc_in_msg;

/* instrumentation */
uint32_t		    gpsc_boot_time;		// time it took to boot.
uint32_t		    gpsc_cycle_time;		// time last cycle took
uint32_t		    gpsc_max_cycle;		// longest cycle time.

#ifdef GPS_LOG_EVENTS

norace uint16_t g_idx;                  /* index into gbuf */

#ifdef GPS_EAVESDROP
#define GPS_EAVES_SIZE 2048

norace uint8_t  gbuf[GPS_EAVES_SIZE];
#endif

typedef struct {
  uint32_t     ts;                      /* Tmilli */
  uint32_t     us;                      /* raw usecs, Tmicro */
  gps_event_t  ev;
  gpsc_state_t gc_state;
  uint32_t     arg;
  uint16_t     g_idx;
} gps_ev_t;

#define GPS_MAX_EVENTS 32

gps_ev_t g_evs[GPS_MAX_EVENTS];
uint8_t g_nev;                          // next gps event

#endif   // GPS_LOG_EVENTS


module ubloxZoeP {
  provides {
    interface Boot as Booted;           /* out Boot */
    interface GPSControl;
    interface MsgTransmit;
  }
  uses {
    interface Boot;                     /* in Boot */

    interface ubloxHardware as HW;
    interface Timer<TMilli> as GPSTxTimer;
    interface Timer<TMilli> as GPSRxTimer;
    interface LocalTime<TMilli>;

    interface MsgBuf;
    interface GPSProto as ubxProto;

    interface Panic;
    interface Platform;
    interface Collect;
    interface CollectEvent;
    interface OverWatch;
//  interface Trace;
  }
}
implementation {

  uint32_t t_gps_pwr_on;                // when driver started
  uint32_t t_gps_first_char;            // from boot

  norace uint32_t m_rx_errors;          // rx errors from the h/w
         uint32_t m_lost_tx_ints;       // on_tx, time outs
         uint32_t m_lost_tx_retries;
         uint32_t m_tx_time_out;        // last tx timeout used


  void gps_warn(uint8_t where, parg_t p, parg_t p1) {
    call Panic.warn(PANIC_GPS, where, p, p1, 0, 0);
  }

  void gps_panic(uint8_t where, parg_t p, parg_t p1) {
    call Panic.panic(PANIC_GPS, where, p, p1, 0, 0);
  }


  /* collect_gps_pak
   *
   * add a gps packet to the data stream.  Debugging etc.
   */
  static void collect_gps_pak(uint8_t *pak, uint16_t len, uint8_t dir) {
    dt_gps_t hdr;

    if (call OverWatch.getLoggingFlag(OW_LOG_GPS_RAW)) {
      hdr.len      = sizeof(hdr) + len;
      hdr.dtype    = DT_GPS_RAW;
      hdr.mark_us  = 0;
      hdr.chip_id  = (*pak == '$') ? CHIP_GPS_NMEA : CHIP_GPS_ZOE;
      hdr.dir      = dir;

      /* time stamp added by Collect */
      call Collect.collect((void *) &hdr, sizeof(hdr), pak, len);
    }
  }


  /* gps log event */
  void gpsc_log_event(gps_event_t ev, uint32_t arg) {
#ifdef GPS_LOG_EVENTS
    uint8_t idx;

    atomic {
      idx = g_nev++;
      if (g_nev >= GPS_MAX_EVENTS)
	g_nev = 0;
      g_evs[idx].ts = call LocalTime.get();
      g_evs[idx].us = call Platform.usecsRaw();
      g_evs[idx].ev = ev;
      g_evs[idx].gc_state = gpsc_state;
      g_evs[idx].arg = arg;
      g_evs[idx].g_idx = g_idx;
    }
#endif
  }


  void gps_wakeup() { }
  void gps_reset()  { }


  /*
   * gps_hibernate: switch off gps, check to see if it is already off first
   */
  void gps_hibernate() { }

  void gpsc_change_state(gpsc_state_t next_state, gps_where_t where) {
#ifdef GPS_DEBUG_DEV
    if (next_state != gpsc_state) {
      WIGGLE_TELL; WIGGLE_TELL; WIGGLE_TELL; WIGGLE_TELL; WIGGLE_TELL;
      nop(); nop(); nop(); nop(); nop(); nop(); nop(); nop(); nop(); nop();
      switch (next_state) {
        default:                        WIGGLE_TELL;
                                        WIGGLE_TELL;
        case GPSC_FAIL:                 WIGGLE_TELL;
        case GPSC_RESET_WAIT:           WIGGLE_TELL;
        case GPSC_HIBERNATE:            WIGGLE_TELL;
        case GPSC_PWR_UP_WAIT:          WIGGLE_TELL;
        case GPSC_VER_DONE:             WIGGLE_TELL;
        case GPSC_VER_WAIT:             WIGGLE_TELL;
        case GPSC_CONFIG_DONE:          WIGGLE_TELL;
        case GPSC_CONFIG_TXRDY_ACK:     WIGGLE_TELL;
        case GPSC_CONFIG_SET_TXRDY:     WIGGLE_TELL;
        case GPSC_CONFIG_CHK:           WIGGLE_TELL;
        case GPSC_CONFIG_BOOT:          WIGGLE_TELL;
        case GPSC_ON_RX_TX:             WIGGLE_TELL;
        case GPSC_ON_TX:                WIGGLE_TELL;
        case GPSC_ON_RX:                WIGGLE_TELL;
        case GPSC_ON:                   WIGGLE_TELL;
      }
    }
#endif
    gpsc_state = next_state;
    gpsc_log_event(GPSE_STATE, where);
  }


  /*
   * GPSControl.turnOn: start up the gps receiver chip
   */
  command error_t GPSControl.turnOn() {
    if (gpsc_state != GPSC_OFF) {
      return EALREADY;
    }

    t_gps_pwr_on = call LocalTime.get();
    call HW.gps_pwr_on();
    call HW.gps_txrdy_int_disable();        /* no need for it yet. */

    /* turning on the Ublox Zoe anecdotally takes about 68ms.  Give it more time */
    call GPSTxTimer.startOneShot(DT_GPS_PWR_UP_DELAY);
    gpsc_change_state(GPSC_PWR_UP_WAIT, GPSW_TURNON);
    call CollectEvent.logEvent(DT_EVENT_GPS_TURN_ON, t_gps_pwr_on, 0, 0, 0);
    return SUCCESS;
  }


  /*
   * GPSControl.turnOff: Stop all GPS activity.
   */
  command error_t GPSControl.turnOff() {
    if (gpsc_state == GPSC_OFF) {
      gps_warn(10, gpsc_state, 0);
    }
    call CollectEvent.logEvent(DT_EVENT_GPS_TURN_OFF, 0, 0, 0, 0);
    call HW.gps_txrdy_int_disable();
    call GPSTxTimer.stop();
    call GPSRxTimer.stop();
    call HW.gps_pwr_off();
    gpsc_change_state(GPSC_OFF, GPSW_TURNOFF);
    return SUCCESS;
  }


  /*
   * GPSControl.standby: Put the GPS chip into standby.
   */
  command error_t GPSControl.standby() {
    gps_hibernate();
    call HW.gps_txrdy_int_disable();
    call GPSTxTimer.stop();
    call GPSRxTimer.stop();
    gpsc_change_state(GPSC_HIBERNATE, GPSW_STANDBY);
    call CollectEvent.logEvent(DT_EVENT_GPS_STANDBY, 0, 0, 0, 0);
    return SUCCESS;
  }


  command void GPSControl.hibernate() {
    gps_hibernate();
  }


  command void GPSControl.wake() {
    gps_wakeup();
  }


  command void GPSControl.pulseOnOff() { }

  command bool GPSControl.awake()      {
    return 0;
  }

  command void GPSControl.reset() { }

  command void GPSControl.powerOn() {
    call HW.gps_pwr_on();
  }

  command void GPSControl.powerOff() {
    call HW.gps_pwr_off();
  }

  command void GPSControl.logStats() {
    call ubxProto.logStats();
  }


  command void MsgTransmit.send(uint8_t *ptr, uint16_t len) {
    collect_gps_pak((void *) ptr, len, GPS_DIR_TX);
    call HW.gps_send((void *) ptr, len);
  }


  event void HW.gps_send_done(error_t err) {
    switch(gpsc_state) {
      default:
        gps_panic(14, gpsc_state, 0);
        return;

      case GPSC_ON:                     /* switch to default later */
      case GPSC_ON_RX:
      case GPSC_ON_TX:
      case GPSC_ON_RX_TX:
        call GPSTxTimer.stop();         /* turn off the TX timer, done. */
        signal MsgTransmit.send_done(SUCCESS);
        return;
    }
  }


  command void MsgTransmit.send_abort() { }
  default event void MsgTransmit.send_done(error_t err) { }

  /*
   * GPSTxTimer.fired
   * TX deadman timer, also used for power on timing.
   */
  event void GPSTxTimer.fired() {
    atomic {
      switch (gpsc_state) {
        default:                        /* all other states blow up */
          gps_panic(15, gpsc_state, 0);
          /* dead*/

        case GPSC_PWR_UP_WAIT:
          gpsc_log_event(GPSE_TIMEOUT, call Platform.usecsRaw());
          gpsc_change_state(GPSC_ON, GPSW_TX_TIMER);
          call HW.gps_txrdy_int_enable();      /* turn on txrdy interrupt */
          signal GPSControl.gps_booted();
          break;

        case GPSC_ON:
        case GPSC_ON_RX:
        case GPSC_ON_TX:
        case GPSC_ON_RX_TX:
          break;
      }
    }
  }


  /*
   * GPSRxTimer.fired - handle receive state machine related timeouts
   */
  event void GPSRxTimer.fired() {
    atomic {
      switch (gpsc_state) {
        default:
          gps_panic(16, gpsc_state, 0);
          return;

        case GPSC_ON_RX:
          call ubxProto.rx_timeout();
          gpsc_change_state(GPSC_ON, GPSW_RX_TIMER);
          return;

        case GPSC_ON_RX_TX:
          call ubxProto.rx_timeout();
          gpsc_change_state(GPSC_ON_TX, GPSW_RX_TIMER);
          return;
      }
    }
  }


  event void ubxProto.msgStart(uint16_t len) {
    gpsc_state_t next_state;

    gpsc_in_msg = TRUE;
    switch(gpsc_state) {
      default:
        gps_panic(17, gpsc_state, 0);
        return;

        /* not running any time out, stand alone */
      case GPSC_CONFIG_BOOT:            /* stay */
      case GPSC_CONFIG_CHK:
      case GPSC_CONFIG_SET_TXRDY:
      case GPSC_CONFIG_TXRDY_ACK:
      case GPSC_CONFIG_DONE:
      case GPSC_VER_WAIT:
      case GPSC_VER_DONE:
        gpsc_change_state(gpsc_state, GPSW_PROTO_START);
        return;
      case GPSC_ON:      next_state = GPSC_ON_RX;         break;
      case GPSC_ON_TX:   next_state = GPSC_ON_RX_TX;      break;
    }
    call GPSRxTimer.startOneShot(DT_GPS_MAX_RX_TIMEOUT);
    gpsc_change_state(next_state, GPSW_PROTO_START);
  }


  event void ubxProto.msgEnd() {
    gpsc_state_t next_state;

    gpsc_in_msg = FALSE;
    switch(gpsc_state) {
      default:
        gps_panic(19, gpsc_state, 0);
        return;

      case GPSC_CONFIG_BOOT:            /* stay */
      case GPSC_CONFIG_CHK:
      case GPSC_CONFIG_SET_TXRDY:
      case GPSC_CONFIG_TXRDY_ACK:
      case GPSC_CONFIG_DONE:
      case GPSC_VER_WAIT:
      case GPSC_VER_DONE:
        next_state = gpsc_state;
        break;

      case GPSC_ON_RX:    next_state = GPSC_ON;    break;
      case GPSC_ON_RX_TX: next_state = GPSC_ON_TX; break;
    }
    call GPSRxTimer.stop();
    gpsc_change_state(next_state, GPSW_PROTO_END);
  }


  void driver_protoAbort(uint16_t reason) {
    gpsc_state_t next_state;

    gpsc_in_msg = FALSE;
    gpsc_log_event(GPSE_ABORT, reason);
    switch(gpsc_state) {
      default:
        gps_panic(18, gpsc_state, 0);
        return;

      case GPSC_CONFIG_BOOT:
      case GPSC_CONFIG_CHK:
      case GPSC_CONFIG_SET_TXRDY:
      case GPSC_CONFIG_TXRDY_ACK:
      case GPSC_CONFIG_DONE:
      case GPSC_VER_WAIT:
      case GPSC_VER_DONE:
      case GPSC_ON:
        gpsc_change_state(gpsc_state, GPSW_PROTO_ABORT);
        return;

        /* something went wrong after we got the msgStart. */
      case GPSC_ON_RX:    next_state = GPSC_ON;    break;
      case GPSC_ON_RX_TX: next_state = GPSC_ON_TX; break;
    }
    call GPSRxTimer.stop();
    gpsc_change_state(next_state, GPSW_PROTO_ABORT);
  }


  event void ubxProto.protoAbort(uint16_t reason) {
    driver_protoAbort(reason);
  }


  /*
   * capture the byte in the eavesdrop buffer
   * TRUE says it matters
   * FALSE says punt
   */
  bool capture_byte(uint8_t byte) {
    if (byte == 0xff && !gpsc_in_msg) {
      /* 0xff is the idle byte, if outside of a message ignore */
      return FALSE;
    }
    if (!t_gps_first_char)
      t_gps_first_char = call LocalTime.get();

#ifdef GPS_EAVESDROP
    gbuf[g_idx++] = byte;
    if (g_idx >= GPS_EAVES_SIZE)
      g_idx = 0;
#endif
    return TRUE;
  }


  uint8_t *collect_pak(uint16_t *lenp) {
    rtctime_t *rtp;
    uint32_t   markp;
    uint8_t   *rx_msg;

    rx_msg = call MsgBuf.msg_next(lenp, &rtp, &markp);
    if (!rx_msg)
      gps_panic(0, 0, 0);
    collect_gps_pak(rx_msg, *lenp, GPS_DIR_RX);
    return rx_msg;
  }

  event void HW.gps_byte_avail(uint8_t byte) {
    if (capture_byte(byte))
      call ubxProto.byteAvail(byte);
  }


  /*
   * returns TRUE if state change
   */
  bool process_byte(uint8_t byte) {
    uint8_t *rx_msg;
    uint16_t rx_len;
    bool     rtn;
    ubx_cfg_prt_t *ubx_prt;
    ubx_ack_t     *ubx_ack;
    ubx_header_t  *ubx_hdr;

    rtn = FALSE;
    if (capture_byte(byte)) {
      if (call ubxProto.byteAvail(byte)) {
        /* true return, says just completed a msg, process it */
        do {
          rx_msg = collect_pak(&rx_len);
          if (!rx_msg)
            return FALSE;
          if (rx_msg[0] == '$')         /* nmea */
            break;
          switch (gpsc_state) {
            default:
              break;

            case GPSC_CONFIG_CHK:
            case GPSC_CONFIG_SET_TXRDY:
              ubx_prt = (void *) rx_msg;
              if (ubx_prt->class   != UBX_CLASS_CFG    ||
                  ubx_prt->id      != UBX_CFG_PRT      ||
                  ubx_prt->portId  != UBX_COM_PORT_SPI)
                break;

              /*
               * if txReady is already set, transition into
               * CONFIG_DONE.  If not, CONFIG_SET_TXRDY
               */
              if (ubx_prt->txReady == UBX_TXRDY_VAL)
                gpsc_change_state(GPSC_CONFIG_DONE, GPSW_BOOT);
              else
                gpsc_change_state(GPSC_CONFIG_SET_TXRDY, GPSW_BOOT);
              rtn = TRUE;
              break;


            case GPSC_CONFIG_TXRDY_ACK:
              ubx_ack = (void *) rx_msg;
              if (ubx_ack->class    != UBX_CLASS_ACK    ||
                  ubx_ack->id       != UBX_ACK_ACK      ||
                  ubx_ack->len      != 2                ||
                  ubx_ack->ackClass != UBX_CLASS_CFG    ||
                  ubx_ack->ackId    != UBX_CFG_PRT)
                break;

              /*
               * stop collecting messages (rtn TRUE) and tell
               * the state machine to verify the configuration.
               */
              gpsc_change_state(GPSC_CONFIG_CHK, GPSW_BOOT);
              rtn = TRUE;
              break;

            case GPSC_VER_WAIT:
              ubx_hdr = (void *) rx_msg;
              if (ubx_hdr->class   != UBX_CLASS_MON    ||
                  ubx_hdr->id      != UBX_MON_VER      ||
                  ubx_hdr->len     <  40)
                break;
              gpsc_change_state(GPSC_VER_DONE, GPSW_BOOT);
              rtn = TRUE;
              break;
          }
        } while (0);
        call MsgBuf.msg_release();
      }
    }
    return rtn;
  }


  void ubx_send_msg(uint8_t *msg, uint16_t len) {
    uint8_t data;

    collect_gps_pak(msg, len, GPS_DIR_TX);
    call HW.spi_put(0xff);
    while (len) {
      data = call HW.spi_getput(*msg++);
      len--;
      process_byte(data);
    }
    data = call HW.spi_get();
    process_byte(data);
  }


  /*
   * ubx_get_msgs: snag one or more messages from the pipe.
   *     terminates when we either timeout (duration) or a state change
   *     has occured.  (see process_byte()).
   *
   * input:     duration, max duration to look
   *            use_txrdy, TRUE if use hw txrdy line.
   * output:    indirect (see below).
   *
   * if use_txrdy is set, we will use TXRDY as the indicator that bytes are
   * in the pipe.  Otherwise, we will loop pulling bytes from the pipe (will
   * be idle bytes if empty).
   *
   * On entry we will loop looking for the start of a packet, we will look
   * for a maximum of "duration".
   *
   * Once we have seen non-idle packet data, we will pull bytes and feed them
   * to the protocol engine via "process_byte()".  If packet processing causes
   * a state change (see process_byte()), we will stop collecting messages.
   *
   * If no state change has occured, we will collect messages for a maximum
   * of "duration".
   */

  void ubx_get_msgs(uint32_t duration, bool use_txrdy) {
    uint8_t  data;
    uint32_t t0, t1;
    uint32_t dwn_cnt;

    dwn_cnt = 8;
    t0 = call Platform.usecsRaw();
    if (use_txrdy) {
      while (TRUE) {
        t1 = call Platform.usecsRaw();
        if ((t1 - t0) > duration)
          return;
        if (call HW.gps_txrdy())
          break;
      }
    }

    call HW.spi_put(0xff);
    while (TRUE) {
      t1 = call Platform.usecsRaw();
      if ((t1 - t0) > duration)
        break;
      data = call HW.spi_getput(0xff);

      /* if process_byte returns TRUE there was a state change */
      if (process_byte(data))
        break;
      if (use_txrdy) {
        if (call HW.gps_txrdy()) {
          dwn_cnt = 8;
          continue;
        }
        if (--dwn_cnt == 0)
          break;
      }
    }

    data = call HW.spi_get();
    process_byte(data);
  }


  void ubx_clean_pipe(uint32_t max_duration) {
    uint8_t  data;
    uint32_t t0, t1;
    uint32_t term_left;

    term_left = 8;
    call HW.spi_put(0xff);
    t0 = call Platform.usecsRaw();
    while (TRUE) {
      t1 = call Platform.usecsRaw();
      if ((t1 - t0) > max_duration)
        break;
      data = call HW.spi_getput(0xff);
      process_byte(data);
      if (data == 0xff) {
        if (--term_left == 0)
          break;
      } else
        term_left = 8;
    }
    data = call HW.spi_get();
    process_byte(data);

    /*
     * We don't handle the corner case of seeing a non-ff
     * byte after the pipe has been cleaned.  Doesn't hurt anything
     */
  }


  /*
   * Standalone initilizer for Ubx M8 based gps chips.
   *
   * o get  HW and SW verions to stash
   * o enable TxRdy
   * o verify TxRdy took, need to poll SPI state.
   */

  event void Boot.booted() {
    uint32_t t0, t1;

    if (gpsc_state != GPSC_OFF)
      gps_panic(1, gpsc_state, 0);

    t_gps_pwr_on = call LocalTime.get();
    call HW.gps_txrdy_int_disable();        /* no need for it yet. */
    WIGGLE_EXC;
    gpsc_change_state(GPSC_CONFIG_BOOT, GPSW_BOOT);
    call CollectEvent.logEvent(DT_EVENT_GPS_BOOT, t_gps_pwr_on, 0, 0, 0);
    if (!call HW.gps_powered())
      call HW.gps_pwr_on();
    call HW.gps_set_reset();
    t0 = call Platform.usecsRaw();
    while (1) {
      t1 = call Platform.usecsRaw();
      if (t1 - t0 > 104858)
        break;
    }
    call HW.gps_clr_reset();
    t0 = call Platform.usecsRaw();
    while (1) {
      t1 = call Platform.usecsRaw();
      if (t1 - t0 > 104858)
        break;
    }
    WIGGLE_EXC;
    ubx_clean_pipe(209715);             /* 200 ms, or empty pipe */

    gpsc_change_state(GPSC_CONFIG_CHK, GPSW_BOOT);
    t0 = call Platform.usecsRaw();
    do {
      t1 = call Platform.usecsRaw();
      if (t1 - t0 > 524288)
        gps_panic(1, gpsc_state, t1 - t0);

      ubx_send_msg((void *) ubx_cfg_prt_poll_spi,  sizeof(ubx_cfg_prt_poll_spi));
      WIGGLE_EXC;
      ubx_get_msgs(104858, FALSE);
      WIGGLE_EXC;
      /*
       * "State" tells the story of what happened if anything.
       *
       * o GPSC_CONFIG_CHK: poll_spi must have gotten clobbered, just send the
       *     prt_spi_txrdy command anyway.
       * o GPSC_CONFIG_SET_TXRDY: got the poll_spi_rsp but txrdy isn't set
       *     to the desirec value.
       * o GPSC_CONFIG_DONE: saw a good response to the poll_spi.  TxRdy is set
       *     properly.  Just move on.
       *
       * After forcing the spi_txrdy, loop back and do a spi_poll to make sure
       * that it took.
       *
       * We will try for a maximum of about 100ms.
       */
      if (gpsc_state != GPSC_CONFIG_DONE) {
        /*
         * We want to reconfigure the SPI port to enable the TXRDY pin.
         *
         * First we suck any pending data from the pipe, this most likely
         * is the ACK for an early prt_spi_poll message.  This ack looks
         * exactly the same as the ACK for the prt_spi_txrdy message.
         *
         * After we send the prt_spi_txrdy message, the ublox will reset
         * the spi pipeline.  This will mess with any packet in progress.
         * After the configuration is complete, the ublox will place the
         * ack response into the spi pipeline.  This is the ack we look
         * for.  We then return to CONFIG_CHK to verify that txrdy has
         * been properly set.
         *
         * The only real effect of this it will shorten the time to
         * configuration complete because it makes ubx_get_msgs() return
         * before the end of the duration.
         *
         * Once we see the ACK for the PRT_SPI_TXRDY message we know it
         * is safe to send the verification poll.  That the spi pipe won't
         * get wacked.  The wackage has been completed.
         */
        ubx_clean_pipe(209715);             /* 200 ms, or empty pipe */
        gpsc_change_state(GPSC_CONFIG_TXRDY_ACK, GPSW_BOOT);
        ubx_send_msg((void *) ubx_cfg_prt_spi_txrdy, sizeof(ubx_cfg_prt_spi_txrdy));
        WIGGLE_EXC;
        ubx_get_msgs(104858, FALSE);
        WIGGLE_EXC;
      }
    } while (gpsc_state != GPSC_CONFIG_DONE);

    gpsc_change_state(GPSC_VER_WAIT, GPSW_BOOT);
    WIGGLE_EXC;
    ubx_clean_pipe(104858);
    WIGGLE_EXC;
    ubx_send_msg((void *) ubx_mon_hw_poll, sizeof(ubx_mon_hw_poll));
    t0 = call Platform.usecsRaw();
    while (TRUE) {
      t1 = call Platform.usecsRaw();
      if (t1 - t0 > 104858)
        gps_panic(16, gpsc_state, 0);
      WIGGLE_EXC;
      ubx_send_msg((void *) ubx_mon_ver_poll, sizeof(ubx_mon_ver_poll));
      WIGGLE_EXC;
      ubx_get_msgs(104858, TRUE);
      WIGGLE_EXC;
      if (gpsc_state == GPSC_VER_DONE)
        break;
    }

    WIGGLE_TELL;
    ubx_clean_pipe(104858);
    WIGGLE_TELL;
    WIGGLE_TELL;
    gpsc_change_state(GPSC_ON, GPSW_BOOT);
    nop();
    call HW.gps_txrdy_int_enable();
    signal Booted.booted();
  }


        event void Collect.collectBooted() { }
  async event void Panic.hook() { }

  default event void GPSControl.standbyDone()   { };
  default event void GPSControl.gps_boot_fail() { };
  default event void GPSControl.gps_booted()    { };
  default event void GPSControl.gps_shutdown()  { };
}

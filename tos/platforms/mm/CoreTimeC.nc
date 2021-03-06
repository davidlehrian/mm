/*
 * Copyright (c) 2018 Eric B. Decker
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
configuration CoreTimeC {
  provides {
    interface Rtc;
    interface RtcAlarm;
    interface RtcEvent;
    interface CoreTime;
    interface TimeSkew;
    interface Boot as Booted;           /* outgoing */
  }
  uses {
    interface Boot;                     /* incoming */
  }
}
implementation {
  components CoreTimeP;
  CoreTime = CoreTimeP;
  TimeSkew = CoreTimeP;
  Booted   = CoreTimeP;
  Boot     = CoreTimeP;
  Rtc      = CoreTimeP.CoreRtc;

  components Msp432RtcC;
  RtcAlarm = Msp432RtcC;
  RtcEvent = Msp432RtcC;
  CoreTimeP.Rtc            -> Msp432RtcC;
  CoreTimeP.RtcHWInterrupt <- Msp432RtcC;

  components CollectC;
  CoreTimeP.Collect      -> CollectC;
  CoreTimeP.CollectEvent -> CollectC;

  components OverWatchC;
  CoreTimeP.OverWatch -> OverWatchC;

  components McuSleepC;
  CoreTimeP.McuSleep -> McuSleepC;

  components PlatformC;
  CoreTimeP.Platform -> PlatformC;

  components PanicC;
  CoreTimeP.Panic -> PanicC;
}

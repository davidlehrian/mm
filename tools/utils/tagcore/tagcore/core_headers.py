# Copyright (c) 2017-2018, Daniel J. Maltbie, Eric B. Decker
# All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
# See COPYING in the top level directory of this source tree.
#
# Contact: Daniel J. Maltbie <dmaltbie@daloma.org>
#          Eric B. Decker <cire831@gmail.com>

'''Core Data Type decoders and objects'''

from   __future__         import print_function

__version__ = '0.3.3.dev1'

import binascii
from   collections  import OrderedDict

from   base_objs    import *
from   sirf_headers import obj_sirf_hdr
from   sirf_headers import obj_sirf_swver

from   sirf_defs    import *
import sirf_defs    as     sirf


########################################################################
#
# Core Decoders
#
########################################################################

#
# GPS RAW decoder
#
# main gps raw decoder, decodes DT_GPS_RAW_SIRFBIN
# dt_gps_raw_obj, 2nd level decode on mid
#
# obj must be a obj_dt_gps_raw.
#
# this decoder does the following:  (it is not a simple decode_default)
#
# o consume/process a gps_raw_hdr (dt_hdr + gps_hdr)
# o consume/process the sirfbin hdr (SOP + LEN + MID)
# o checks the sirfbin hdr for proper SOP.
#
# Not a sirfbin packet:
# o only consume up to the beginning of the SOP
#
# SirfBin packet:
# o Look mid up in mid_table
# o consume/process the remainder of the packet using the appropriate decoder

def decode_gps_raw(level, offset, buf, obj):
    consumed = obj.set(buf)

    if obj['sirf_hdr']['start'].val != SIRF_SOP_SEQ:
        return consumed - len(obj['sirf_hdr'])

    mid = obj['sirf_hdr']['mid'].val

    try:
        sirf.mid_count[mid] += 1
    except KeyError:
        sirf.mid_count[mid] = 1

    v = sirf.mid_table.get(mid, (None, None, None, ''))
    decoder     = v[MID_DECODER]            # dt function
    decoder_obj = v[MID_OBJECT]             # dt object
    if not decoder:
        if (level >= 5):
            print('*** no decoder/obj defined for mid {}'.format(mid))
        return consumed
    return consumed + decoder(level, offset, buf[consumed:], decoder_obj)


########################################################################
#
# Core Header objects
#
########################################################################

def obj_rtctime():
    return aggie(OrderedDict([
        ('sub_sec', atom(('<H', '{}'))),
        ('sec',     atom(('<B', '{}'))),
        ('min',     atom(('<B', '{}'))),
        ('hr',      atom(('<B', '{}'))),
        ('dow',     atom(('<B', '{}'))),
        ('day',     atom(('<B', '{}'))),
        ('mon',     atom(('<B', '{}'))),
        ('year',    atom(('<H', '{}'))),
    ]))


def obj_dt_hdr():
    return aggie(OrderedDict([
        ('len',     atom(('<H', '{}'))),
        ('type',    atom(('<H', '{}'))),
        ('recnum',  atom(('<I', '{}'))),
        ('rt',      obj_rtctime()),
        ('recsum',  atom(('<H', '0x{:04x}'))),
    ]))


def obj_dt_reboot():
    return aggie(OrderedDict([
        ('hdr',       obj_dt_hdr()),
        ('prev_sync', atom(('<I', '{:08x}'))),
        ('majik',     atom(('<I', '{:08x}'))),
        ('core_rev',  atom(('<H', '{:04x}'))),
        ('core_minor',atom(('<H', '{:04x}'))),
        ('base',      atom(('<I', '{:08x}'))),
        ('owcb',      obj_owcb())
    ]))


#
# reboot is followed by the ow_control_block
# We want to decode that as well.  native order, little endian.
# see OverWatch/overwatch.h.
#
def obj_owcb():
    return aggie(OrderedDict([
        ('ow_sig',          atom(('<I', '0x{:08x}'))),
        ('rpt',             atom(('<I', '0x{:08x}'))),
        ('boot_time',       obj_rtctime()),
        ('prev_boot',       obj_rtctime()),
        ('reset_status',    atom(('<I', '0x{:08x}'))),
        ('reset_others',    atom(('<I', '0x{:08x}'))),
        ('from_base',       atom(('<I', '0x{:08x}'))),
        ('panic_count',     atom(('<I', '{}'))),
        ('fault_gold',      atom(('<I', '0x{:08x}'))),
        ('fault_nib',       atom(('<I', '0x{:08x}'))),
        ('subsys_disable',  atom(('<I', '0x{:08x}'))),
        ('ow_sig_b',        atom(('<I', '0x{:08x}'))),
        ('ow_req',          atom(('<B', '{}'))),
        ('reboot_reason',   atom(('<B', '{}'))),
        ('ow_boot_mode',    atom(('<B', '{}'))),
        ('owt_action',      atom(('<B', '{}'))),
        ('reboot_count',    atom(('<I', '{}'))),
        ('strange',         atom(('<I', '{}'))),
        ('strange_loc',     atom(('<I', '0x{:04x}'))),
        ('chk_fails',       atom(('<I', '{}'))),
        ('logging_flags',   atom(('<I', '{}'))),
        ('panics_gold',     atom(('<I', '{}'))),
        ('ow_sig_c',        atom(('<I', '0x{:08x}')))
    ]))


def obj_dt_version():
    return aggie(OrderedDict([
        ('hdr',       obj_dt_hdr()),
        ('base',      atom(('<I', '{:08x}'))),
        ('image_info', obj_image_info())
    ]))


def obj_hw_version():
    return aggie(OrderedDict([
        ('rev',       atom(('<B', '{:x}'))),
        ('model',     atom(('<B', '{:x}'))),
    ]))


def obj_image_version():
    return aggie(OrderedDict([
        ('build',     atom(('<H', '{:x}'))),
        ('minor',     atom(('<B', '{:x}'))),
        ('major',     atom(('<B', '{:x}'))),
    ]))


IMG_DESC_MAX = 44
STAMP_MAX    = 30

def obj_image_info():
    return aggie(OrderedDict([
        ('ii_sig',    atom(('<I', '0x{:08x}'))),
        ('im_start',  atom(('<I', '0x{:08x}'))),
        ('im_len',    atom(('<I', '0x{:08x}'))),
        ('ver_id',    obj_image_version()),
        ('im_chk',    atom(('<I', '0x{:08x}'))),
        ('image_desc',atom(('44s', '{:s}'))),
        ('repo0',     atom(('44s', '{:s}'))),
        ('repo1',     atom(('44s', '{:s}'))),
        ('stamp_date',atom(('30s', '{:s}'))),
        ('hw_ver',    obj_hw_version()),
    ]))


def obj_dt_sync():
    return aggie(OrderedDict([
        ('hdr',       obj_dt_hdr()),
        ('prev_sync', atom(('<I', '{:x}'))),
        ('majik',     atom(('<I', '{:08x}'))),
    ]))


# EVENT
event_names = {
    0:  'NONE',

    1:  'PANIC_WARN',

    2:  'GPS_GEO',
    3:  'GPS_XYZ',
    4:  'GPS_TIME',
    5:  'GPS_MTFF_TIME',

    6:  'SSW_DELAY_TIME',
    7:  'SSW_BLK_TIME',
    8:  'SSW_GRP_TIME',

    9:  'SURFACED',
    10: 'SUBMERGED',
    11: 'DOCKED',
    12: 'UNDOCKED',

    32: 'GPS_BOOT',
    33: 'GPS_BOOT_TIME',
    34: 'GPS_BOOT_FAIL',

    35: 'GPS_MON_MINOR',
    36: 'GPS_MON_MAJOR',

    37: 'GPS_RX_ERR',
    38: 'GPS_LOST_INT',
    39: 'GPS_MSG_OFF',

    40: 'GPS_AWAKE_S',
    41: 'GPS_CMD',
    42: 'GPS_RAW_TX',
    43: 'GPS_SWVER_TO',
    44: 'GPS_CANNED',

    45: 'GPS_HW_CONFIG',
    46: 'GPS_RECONFIG',

    47: 'GPS_TURN_ON',
    48: 'GPS_STANDBY',
    49: 'GPS_TURN_OFF',
    50: 'GPS_MPM',
    51: 'GPS_PULSE',

    64: 'GPS_FAST',
    65: 'GPS_FIRST',
    66: 'GPS_SATS_2',
    67: 'GPS_SATS_7',
    68: 'GPS_SATS_41',
}

def event_name(event):
    return event_names.get(event, 'unk')


PANIC_WARN    = 1
GPS_MON_MINOR = 35
GPS_MON_MAJOR = 36
GPS_RX_ERR    = 37
GPS_CMD       = 41


def obj_dt_event():
    return aggie(OrderedDict([
        ('hdr',   obj_dt_hdr()),
        ('event', atom(('<H', '{}'))),
        ('pcode', atom(('<B', '{}'))),
        ('w',     atom(('<B', '{}'))),
        ('arg0',  atom(('<I', '0x{:04x}'))),
        ('arg1',  atom(('<I', '0x{:04x}'))),
        ('arg2',  atom(('<I', '0x{:04x}'))),
        ('arg3',  atom(('<I', '0x{:04x}'))),
    ]))


#
# not implemented yet.
#
obj_dt_debug    = obj_dt_hdr

#
# dt, native, little endian
# used by DT_GPS_VERSION and DT_GPS_RAW_SIRFBIN (gps_raw)
#
def obj_dt_gps_hdr():
    return aggie(OrderedDict([
        ('hdr',     obj_dt_hdr()),
        ('mark',    atom(('<I', '0x{:04x}'))),
        ('chip',    atom(('B',  '0x{:02x}'))),
        ('dir',     atom(('B',  '{}'))),
        ('pad',     atom(('<H', '{}'))),
    ]))


def obj_dt_gps_ver():
    return aggie(OrderedDict([
        ('gps_hdr',    obj_dt_gps_hdr()),
        ('sirf_swver', obj_sirf_swver()),
    ]))

obj_dt_gps_time = obj_dt_hdr
obj_dt_gps_geo  = obj_dt_hdr
obj_dt_gps_xyz  = obj_dt_hdr

obj_dt_sen_data = obj_dt_hdr
obj_dt_sen_set  = obj_dt_hdr

obj_dt_test     = obj_dt_hdr

####
#
# NOTES
#
# A note record consists of a dt_note_t header (same as dt_header_t, a
# simple header) followed by n bytes of note.  typically a printable
# ascii string (yeah, localization is an issue, but not now).
#
obj_dt_note     = obj_dt_hdr
obj_dt_config   = obj_dt_hdr

# DT_GPS_RAW_SIRFBIN, dt, native, little endian
#  sirf data big endian.
def obj_dt_gps_raw():
    return aggie(OrderedDict([
        ('gps_hdr',  obj_dt_gps_hdr()),
        ('sirf_hdr', obj_sirf_hdr()),
    ]))

obj_dt_tagnet   = obj_dt_hdr

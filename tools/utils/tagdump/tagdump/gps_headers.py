#
# Copyright (c) 2017-2018 Eric B. Decker, Daniel J. Maltbie
# All rights reserved.
#
# object descriptors for gps data blocks

from   decode_base  import *
from   collections  import OrderedDict
from   core_headers import dt_hdr_obj
from   core_headers import dt_simple_hdr

dt_gps_ver_obj  = dt_simple_hdr
dt_gps_time_obj = dt_simple_hdr
dt_gps_geo_obj  = dt_simple_hdr
dt_gps_xyz_obj  = dt_simple_hdr

#
# warning GPS messages are big endian.  The surrounding header (the dt header
# etc) is little endian (native order).
#
gps_nav_obj = aggie(OrderedDict([
    ('xpos',  atom(('>i', '{}'))),
    ('ypos',  atom(('>i', '{}'))),
    ('zpos',  atom(('>i', '{}'))),
    ('xvel',  atom(('>h', '{}'))),
    ('yvel',  atom(('>h', '{}'))),
    ('zvel',  atom(('>h', '{}'))),
    ('mode1', atom(('B', '0x{:02x}'))),
    ('hdop',  atom(('B', '0x{:02x}'))),
    ('mode2', atom(('B', '0x{:02x}'))),
    ('week10',atom(('>H', '{}'))),
    ('tow',   atom(('>I', '{}'))),
    ('nsats', atom(('B', '{}')))]))

gps_navtrk_obj = aggie(OrderedDict([
    ('week10', atom(('>H', '{}'))),
    ('tow',    atom(('>I', '{}'))),
    ('chans',  atom(('B',  '{}')))]))

gps_navtrk_chan = aggie([('sv_id',    atom(('B',  '{:2}'))),
                         ('sv_az23',  atom(('B',  '{:3}'))),
                         ('sv_el2',   atom(('B',  '{:3}'))),
                         ('state',    atom(('>H', '0x{:04x}'))),
                         ('cno0',     atom(('B',  '{}'))),
                         ('cno1',     atom(('B',  '{}'))),
                         ('cno2',     atom(('B',  '{}'))),
                         ('cno3',     atom(('B',  '{}'))),
                         ('cno4',     atom(('B',  '{}'))),
                         ('cno5',     atom(('B',  '{}'))),
                         ('cno6',     atom(('B',  '{}'))),
                         ('cno7',     atom(('B',  '{}'))),
                         ('cno8',     atom(('B',  '{}'))),
                         ('cno9',     atom(('B',  '{}')))])

gps_swver_obj   = aggie(OrderedDict([('str0_len', atom(('B', '{}'))),
                                     ('str1_len', atom(('B', '{}')))]))
gps_vis_obj     = aggie([('vis_sats', atom(('B',  '{}')))])
gps_vis_azel    = aggie([('sv_id',    atom(('B',  '{}'))),
                         ('sv_az',    atom(('>h', '{}'))),
                         ('sv_el',    atom(('>h', '{}')))])

# OkToSend
gps_ots_obj = atom(('B', '{}'))

gps_geo_obj = aggie(OrderedDict([
    ('nav_valid',        atom(('>H', '0x{:04x}'))),
    ('nav_type',         atom(('>H', '0x{:04x}'))),
    ('week_x',           atom(('>H', '{}'))),
    ('tow',              atom(('>I', '{}'))),
    ('utc_year',         atom(('>H', '{}'))),
    ('utc_month',        atom(('B', '{}'))),
    ('utc_day',          atom(('B', '{}'))),
    ('utc_hour',         atom(('B', '{}'))),
    ('utc_min',          atom(('B', '{}'))),
    ('utc_ms',           atom(('>H', '{}'))),
    ('sat_mask',         atom(('>I', '0x{:08x}'))),
    ('lat',              atom(('>i', '{}'))),
    ('lon',              atom(('>i', '{}'))),
    ('alt_elipsoid',     atom(('>i', '{}'))),
    ('alt_msl',          atom(('>i', '{}'))),
    ('map_datum',        atom(('B', '{}'))),
    ('sog',              atom(('>H', '{}'))),
    ('cog',              atom(('>H', '{}'))),
    ('mag_var',          atom(('>H', '{}'))),
    ('climb',            atom(('>h', '{}'))),
    ('heading_rate',     atom(('>h', '{}'))),
    ('ehpe',             atom(('>I', '{}'))),
    ('evpe',             atom(('>I', '{}'))),
    ('ete',              atom(('>I', '{}'))),
    ('ehve',             atom(('>H', '{}'))),
    ('clock_bias',       atom(('>i', '{}'))),
    ('clock_bias_err',   atom(('>i', '{}'))),
    ('clock_drift',      atom(('>i', '{}'))),
    ('clock_drift_err',  atom(('>i', '{}'))),
    ('distance',         atom(('>I', '{}'))),
    ('distance_err',     atom(('>H', '{}'))),
    ('head_err',         atom(('>H', '{}'))),
    ('nsats',            atom(('B', '{}'))),
    ('hdop',             atom(('B', '{}'))),
    ('additional_mode',  atom(('B', '0x{:02x}'))),
]))

# gps piece, big endian, follows dt_gps_raw_obj
gps_hdr_obj = aggie(OrderedDict([('start',   atom(('>H', '0x{:04x}'))),
                                 ('len',     atom(('>H', '0x{:04x}'))),
                                 ('mid',     atom(('B', '0x{:02x}')))]))

# dt, native, little endian
dt_gps_raw_obj = aggie(OrderedDict([('hdr',     dt_hdr_obj),
                                    ('chip',    atom(('B',  '0x{:02x}'))),
                                    ('dir',     atom(('B',  '{}'))),
                                    ('mark',    atom(('>I', '0x{:04x}'))),
                                    ('gps_hdr', gps_hdr_obj)]))
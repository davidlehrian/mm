# Copyright (c) 2019 Eric B. Decker
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
# Contact: Eric B. Decker <cire831@gmail.com>

'''
simple globals used across tagcore users.

Includes:

    - verbose:   verbosity level
    - debug:     yep, debug mode
    - export:    export force (1 says forcing export)
                 -1 says --noexport.
    - quiet:     0 if displaying annoying displays
                 1 suppress annoying displays
    - pretty     0 compact (default)
                 1 print pretty (more readable) when able.
    - gps_level: None if not using gps_eval emitters
                 numeric level for how much to display
    - mr_emitters: False, nope
                   True, use machine readable emitters
'''

verbose   = 0
debug     = 0
export    = 0
quiet     = 0
pretty    = 0
gps_level = None
mr_emitters = False

/**
 * @Copyright (c) 2017 Daniel J. Maltbie
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
 * @author Daniel J. Maltbie <dmaltbie@daloma.org>
 */

#include <TagnetTLV.h>

generic module TagnetGpsXyzAdapterImplP (int my_id) @safe() {
  uses interface  TagnetMessage   as  Super;
  uses interface  TagnetAdapter<tagnet_gps_xyz_t> as Adapter;
  uses interface  TagnetName      as  TName;
  uses interface  TagnetHeader    as  THdr;
  uses interface  TagnetPayload   as  TPload;
  uses interface  TagnetTLV       as  TTLV;
}
implementation {
  enum { my_adapter_id = unique(UQ_TAGNET_ADAPTER_LIST) };
  uint32_t last_sequence = 0;

  event bool Super.evaluate(message_t *msg) {
    tagnet_gps_xyz_t        v = {0,0,0};
    uint32_t               ln = 0;
    tagnet_tlv_t    *name_tlv = (tagnet_tlv_t *)tn_name_data_descriptors[my_id].name_tlv;
    tagnet_tlv_t    *this_tlv = call TName.this_element(msg);
    tagnet_tlv_t    *offset_tlv;

    call THdr.set_response(msg);
    if (call TTLV.eq_tlv(name_tlv, this_tlv)) {
      tn_trace_rec(my_id, 1);
      call THdr.set_error(msg, TE_PKT_OK);
      switch (call THdr.get_message_type(msg)) {      // process message type
        case TN_GET:
          tn_trace_rec(my_id, 2);
          call TPload.reset_payload(msg);
          offset_tlv = call TName.get_offset(msg);
          if ((offset_tlv) && (call TTLV.tlv_to_offset(offset_tlv))) {
            tn_trace_rec(my_id, 3);
            call TPload.add_error(msg, EODATA); // non-zero offset not accepted
          }
          else if (call Adapter.get_value(&v, &ln)) {
            call TPload.add_gps_xyz(msg, &v);
            call TPload.add_error(msg, EODATA);
          } else {
            tn_trace_rec(my_id, 4);
            call TPload.add_error(msg, EINVAL);
          }
          call THdr.set_response(msg);
          return TRUE;

        case TN_PUT:
          tn_trace_rec(my_id, 5);
          if (call Adapter.set_value(&v, &ln)) {
            tn_trace_rec(my_id, 6);
            call TPload.add_error(msg, EODATA);
          } else {
            tn_trace_rec(my_id, 7);
            call TPload.add_error(msg, EINVAL);
          }
          call TPload.add_size(msg, ++last_sequence);
          call TPload.reset_payload(msg);
          call THdr.set_response(msg);
          return TRUE;

        case TN_HEAD:
          tn_trace_rec(my_id, 8);
          call TPload.reset_payload(msg);
          call TPload.add_size(msg, sizeof(v));    // value is used for file size
          call THdr.set_response(msg);
          return TRUE;

        default:
          break;
      }
    }
    call THdr.set_error(msg, TE_PKT_NO_MATCH);
    tn_trace_rec(my_id, 255);
    return FALSE;
  }

  event void Super.add_name_tlv(message_t* msg) {
    tagnet_tlv_t    *name_tlv = (tagnet_tlv_t *)tn_name_data_descriptors[my_id].name_tlv;

    call TPload.add_tlv(msg, name_tlv);
  }

  event void Super.add_value_tlv(message_t* msg) {
    tagnet_gps_xyz_t        v;
    uint32_t                ln;

    if (call Adapter.get_value(&v, &ln)) {
      call TPload.add_gps_xyz(msg, &v);
    }
//      panic();
  }

  event void Super.add_help_tlv(message_t* msg) {
    tagnet_tlv_t    *help_tlv = (tagnet_tlv_t *)tn_name_data_descriptors[my_id].help_tlv;

    call TPload.add_tlv(msg, help_tlv);
  }
}

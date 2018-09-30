/*
 * Copyright 2008, 2014, 2017-2018: Eric B. Decker
 * All rights reserved.
 * Mam-Mark Project
 *
 * CollectP.nc - data collector (record managment) interface
 * between data collection and mass storage.
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
 * Collect/RecSum: Record Checksum Implementation
 *
 * Collect records and kick them to Stream Storage.
 *
 * Originally, we provided for data integrity by a single checksum
 * and a sequence number on each sector.  This however, requires
 * a three level implementation to recover split records.
 *
 * Replacing this with a per record checksum results in both the sector
 * checksum and sequence number disappearing.  This greatly simplifies
 * the software implementation and collapses the layers into one.
 *
 * See typed_data.h for details on how the headers are layed out.
 *
 * Mass Storage block size is 512.  If this changes the tag is severly
 * bolloxed as this number is spread a number of different places.  Fucked
 * but true.  Collect uses the entire underlying sector.  This is
 * SD_BLOCKSIZE.  There is no point in abstracting this at the
 * StreamStorage layer.  SD block size permeats too many places.  And it
 * doesn't change.
 *
 * Data associated with a given header however can be split across sector
 * boundaries but is limited to DT_MAX_DLEN.  (defined in typed_data.h).
 *
 * Collect is responsible for laying down REBOOT records on the way up and
 * SYNC records at appropriate times/events.  We primarily lay down SYNCs
 * based on how many sectors (buffers) have been written.  In addition, as
 * a fail safe, we also start a timer after any SYNC as been written.  If
 * the timer expires, we lay down a SYNC.
 *
 * Collect is responsible for managing prev_sync file offsets.  This a
 * combination of blk_id and byte offset within the buffer of the SYNC or
 * REBOOT being lay'd down.
 */

#include <core_rev.h>
#include <typed_data.h>
#include <image_info.h>
#include <overwatch.h>
#include <stream_storage.h>
#include <sd.h>

/*
 * Data Collector (dc) control structure
 *
 * The data collector is the record marshaller and lays records down into
 * the underlying SD buffers that Stream Storage (SSW) gives us.
 *
 * remaining:           number of bytes still remaining in current buffer
 * handle:              keeper of the current SSW handle
 * cur_buf:             extracted start of the buffer from the handle
 * cur_ptr:             where in the current buffer we be
 *
 * cur_recnum:          last recnum used.
 * last_rec_offset:     file offset of last record laid down
 * last_sync_offset:    file offset of last REBOOT/SYNC laid down
 * bufs_to_next_sync:   number of buffers/sectors before we do next sync

 * DblkManager is responsible for keeping track of where in the Data Stream
 * we are.
 */
typedef struct {
  uint16_t     majik_a;

  uint16_t     remaining;
  ss_wr_buf_t *handle;
  uint8_t     *cur_buf;
  uint8_t     *cur_ptr;

  uint32_t     cur_recnum;              /* last record used */
  uint32_t     last_rec_offset;         /* file offset */
  uint32_t     last_sync_offset;        /* file offset */
  uint16_t     bufs_to_next_sync;
  uint16_t     cur_year;

  uint16_t     majik_b;
} dc_control_t;

#define DC_MAJIK 0x1008


extern image_info_t image_info;
extern ow_control_block_t ow_control_block;


module CollectP {
  provides {
    /* externals */
    interface Boot as Booted;           /* out boot */
    interface Boot as EndOut;           /* out boot */
    interface Collect;
    interface CollectEvent;

    interface TagnetAdapter<uint32_t> as DblkLastRecNum;
    interface TagnetAdapter<uint32_t> as DblkLastRecOffset;
    interface TagnetAdapter<uint32_t> as DblkLastSyncOffset;
    interface TagnetAdapter<uint32_t> as DblkCommittedOffset;
    interface TagnetAdapter<uint32_t> as DblkResyncOffset;

    /* private */
    interface Init;                     /* SoftwareInit */
  }
  uses {
    /* externals */
    interface Boot;                     /* in boot in sequence */
    interface Boot as EndIn;            /* in boot for end of SysBoot */

    /* private */
    interface Boot as SysBoot;          /* use at end of System Boot initilization */
    interface Timer<TMilli> as SyncTimer;
    interface OverWatch;
    interface Rtc;
    interface Crc<uint8_t> as Crc8;

    interface SSWrite as SSW;
    interface StreamStorage as SS;
    interface Panic;
    interface DblkManager;
    interface SysReboot @atleastonce();
    interface ByteMapFile as DMF;
    interface Timer<TMilli> as ResyncTimer;
  }
}

implementation {

  norace dc_control_t dcc;


  // structure to manage state variables for reSync operation
  typedef struct {
    uint32_t cur_offset;    /* last place visited */
    uint32_t term_offset;   /* offset to halt search */
    uint32_t found_offset;  /* offset of found sync record, 0 if none */
    bool     in_progress;   /* search already in progress, try later */
    error_t  err;           /* error encountered during search */
  } scb_t;

  /* Sync Search Control Block (scb) */
  scb_t scb = {0, 0, -EINVAL, FALSE, SUCCESS};


  /*
   * get_rec_offset
   * return file offset of where the next record will get laid down
   *
   * Collect MUST lay down records atomically before looking at any
   * record offsets.
   */

  uint32_t get_rec_offset() {
    return call SS.eof_offset();
  }


  void write_version_record() {
    dt_version_t  v;
    dt_version_t *vp;

    vp = &v;
    vp->len     = sizeof(v) + sizeof(image_info_t);
    vp->dtype   = DT_VERSION;
    vp->base    = call OverWatch.getImageBase();
    call Collect.collect((void *) vp, sizeof(dt_version_t),
                         (void *) &image_info, sizeof(image_info_t));
  }


  void write_sync_record(dtype_t dtype) {
    dt_sync_t  s;
    dt_sync_t *sp;

    sp = &s;
    sp->len = sizeof(s);
    sp->dtype = dtype;
    sp->sync_majik = SYNC_MAJIK;
    sp->prev_sync  = dcc.last_sync_offset;
    dcc.last_sync_offset = get_rec_offset();
    call Collect.collect((void *) sp, sizeof(dt_sync_t), NULL, 0);
  }


  void write_reboot_record() {
    dt_reboot_t  r;
    dt_reboot_t *rp;

    write_sync_record(DT_SYNC_REBOOT);
    rp = &r;
    rp->len = sizeof(r) + sizeof(ow_control_block_t);
    rp->dtype = DT_REBOOT;
    rp->core_rev   = CORE_REV;            /* which version of core */
    rp->core_minor = CORE_MINOR;
    rp->base = call OverWatch.getImageBase();
    call Collect.collect((void *) rp, sizeof(r),
                         (void *) &ow_control_block,
                         sizeof(ow_control_block_t));
    call OverWatch.clearReset();        /* clears owcb copies */
    call OverWatch.clearPanicInfo();    /* clear persistant panic info */

    /* clear resetable faults */
    call OverWatch.clrFault(OW_FAULT_LOW_PWR);
  }


  /*
   * Always write the reboot record first.
   *
   * This is the very first record (REBOOT) after we've come up.
   * This will ALWAYS be the first record written to the very
   * first sector that DblkManager has found for where the Data
   * Stream will restart.
   */
  event void Boot.booted() {
    write_reboot_record();
    write_version_record();
    call OverWatch.checkFaults();
    call CollectEvent.logEvent(DT_EVENT_TIME_SRC, call OverWatch.getRtcSrc(),
                               0, 0, 0);
    signal Collect.collectBooted();     /* tell others collect is up */
    signal Booted.booted();
  }


  event void EndIn.booted() {
    call OverWatch.sysBootDone();
    signal EndOut.booted();
  }


  task void collect_sync_task() {
    /*
     * update down counters first, to avoid getting SYNCs very close
     * together.
     */
    dcc.bufs_to_next_sync = SYNC_MAX_SECTORS;
    call SyncTimer.stop();
    write_sync_record(DT_SYNC);
    call OverWatch.checkFaults();
    call SyncTimer.startOneShot(SYNC_PERIOD);
  }


  event void SysBoot.booted() {
    call SyncTimer.startOneShot(SYNC_PERIOD);
  }


  event void SyncTimer.fired() {
    post collect_sync_task();
  }


  command error_t Init.init() {
    dcc.majik_a = DC_MAJIK;
    dcc.majik_b = DC_MAJIK;
    dcc.bufs_to_next_sync = SYNC_MAX_SECTORS;
    return SUCCESS;
  }


  command bool DblkLastRecNum.get_value(uint32_t *t, uint32_t *l) {
    if (!l || !t)
      call Panic.panic(0, 0, 0, 0, 0, 0);
    *t = dcc.cur_recnum;
    *l = sizeof(uint32_t);
    return TRUE;
  }


  command bool DblkLastRecOffset.get_value(uint32_t *t, uint32_t *l) {
    if (!l || !t)
      call Panic.panic(0, 0, 0, 0, 0, 0);
    *t = dcc.last_rec_offset;
    *l = sizeof(uint32_t);
    return TRUE;
  }


  command bool DblkLastSyncOffset.get_value(uint32_t *t, uint32_t *l) {
    if (!l || !t)
      call Panic.panic(0, 0, 0, 0, 0, 0);
    *t = dcc.last_sync_offset;
    *l = sizeof(uint32_t);
    return TRUE;
  }


  command bool DblkCommittedOffset.get_value(uint32_t *t, uint32_t *l) {
    if (!l || !t)
      call Panic.panic(0, 0, 0, 0, 0, 0);
    *t = call SS.committed_offset();
    *l = sizeof(uint32_t);
    return TRUE;
  }


  command bool DblkResyncOffset.get_value(uint32_t *t, uint32_t *l) {
    if (!t || !l)
      call Panic.panic(0, 0, 0, 0, 0, 0);
    *t = scb.in_progress ? 0 : scb.found_offset;
    *l = sizeof(uint32_t);
    return TRUE;
  }


  /**
   * DblkResyncOffset.set_value: start a resync operation
   *
   * initiate search for next sync record if not currently busy. limit
   * how much of file space will be searched to twice the number of
   * sectors in which Collect ensures a sync record is written.
   */
  command bool DblkResyncOffset.set_value(uint32_t *t, uint32_t *l) {
    error_t  err;

    if (!l || !t || *l != sizeof(uint32_t))
      call Panic.panic(0, 0, 0, 0, 0, 0);
    err = call Collect.resyncStart(t, *t + (2 * SYNC_MAX_SECTORS * SD_BLOCKSIZE));
    /* make sure return value indicate waiting for search to complete */
    if (err == EBUSY) *t = 0;
    return TRUE;
  }


  command bool DblkLastRecNum.set_value(uint32_t *t, uint32_t *l)      { return FALSE; }
  command bool DblkLastRecOffset.set_value(uint32_t *t, uint32_t *l)   { return FALSE; }
  command bool DblkLastSyncOffset.set_value(uint32_t *t, uint32_t *l)  { return FALSE; }
  command bool DblkCommittedOffset.set_value(uint32_t *t, uint32_t *l) { return FALSE; }


  /*
   * finish_sector
   *
   * sector is finished, zero dcc.remaining which will force getting
   * another buffer when we have more bytes to write out.
   *
   * Hand the current buffer off to the writer then reinitialize the
   * control cells to no buffer here.
   */
  void finish_sector() {
    nop();                              /* BRK */
    call SSW.buffer_full(dcc.handle);
    if (--dcc.bufs_to_next_sync == 0) {
      post collect_sync_task();
      dcc.bufs_to_next_sync = SYNC_MAX_SECTORS;
    }
    dcc.remaining = 0;
    dcc.handle    = NULL;
    dcc.cur_buf   = NULL;
    dcc.cur_ptr   = NULL;
  }


  void align_next() {
    unsigned int count;
    uint8_t *ptr;

    ptr = dcc.cur_ptr;
    count = (unsigned int) ptr & 0x03;
    if (dcc.remaining == 0 || !count)   /* nothing to align */
      return;
    if (dcc.remaining < 4) {
      finish_sector();
      return;
    }

    /*
     * we know there are at least 5 bytes left
     * chew bytes until aligned.  1, 2, or 3 bytes
     * actually 4 - count at this point.
     *
     * won't change checksum
     */
    switch (count) {
      case 1: *ptr++ = 0;
      case 2: *ptr++ = 0;
      case 3: *ptr++ = 0;
    }
    dcc.cur_ptr = ptr;
    dcc.remaining -= (4 - count);
  }


  /*
   * returns amount actually copied
   */
  static uint16_t copy_block_out(uint8_t *data, uint16_t dlen) {
    uint8_t  *ptr;
    uint16_t num_to_copy;
    unsigned int i;

    num_to_copy = ((dlen < dcc.remaining) ? dlen : dcc.remaining);
    ptr = dcc.cur_ptr;
    for (i = 0; i < num_to_copy; i++)
      *ptr++  = *data++;
    dcc.cur_ptr = ptr;
    dcc.remaining -= num_to_copy;
    return num_to_copy;
  }


  void copy_out(uint8_t *data, uint16_t dlen) {
    uint16_t num_copied;

    if (!data || !dlen)            /* nothing to do? */
      return;
    while (dlen > 0) {
      if (dcc.cur_buf == NULL) {
        /*
         * no space left, get another buffer
         * get_free_buf_handle either works or panics.
         */
        dcc.handle = call SSW.get_free_buf_handle();
        dcc.cur_ptr = dcc.cur_buf = call SSW.buf_handle_to_buf(dcc.handle);
        dcc.remaining = SD_BLOCKSIZE;
      }
      num_copied = copy_block_out(data, dlen);
      data += num_copied;
      dlen -= num_copied;
      if (dcc.remaining == 0)
        finish_sector();
    }
  }


  void finish_record(dt_header_t *header, uint16_t hlen,
                     uint8_t     *data,   uint16_t dlen) {
    uint16_t    chksum;
    uint32_t    i;

    dcc.cur_recnum++;
    dcc.last_rec_offset = get_rec_offset();
    header->recnum = dcc.cur_recnum;

    /*
     * all fields of the header are filled in.  Compute the hdr_crc8
     * It is an external crc.  When checking the crc, one must remember
     * its value, zero its cell, compute the crc, and compare.
     */
    header->hdr_crc8 = 0;
    header->hdr_crc8 = call Crc8.crc((void *) header, sizeof(dt_header_t));

    /*
     * upper layers are responsible for filling in any pad fields,
     * typically 0.  Pad fields are don't care but are part of the record
     * and are significant in the checksum.  We set to zero by convention.
     *
     * we need to compute the record chksum over all bytes of the header and
     * all bytes of the data area.  Additions to the chksum are done byte by
     * byte.  This has to be done before copying any of the data out and added
     * to the header (recsum).  Duh.  In other words, we have to finish updating
     * critical fields in the record header before coping it else where.
     *
     * Set recsum to 0.  Sum byte by byte all header and data bytes.  Then lay
     * in the computed 16 bit result as recsum.
     *
     * To verify, sum all bytes.  This result will include both recsum
     * bytes.  Remove the recsum bytes from result (as individual bytes)
     * and compare the result to recsum itself.  See checksum verify in
     * get_record in tagdump.py.  (tools/utils/tagdump/tagdump)
     */
    chksum = 0;
    header->recsum = 0;
    for (i = 0; i < hlen; i++)
      chksum += ((uint8_t *) header)[i];
    for (i = 0; data && i < dlen; i++)
      chksum += data[i];
    header->recsum = (uint16_t) chksum;
  }


  /*
   * All data fields are assumed to be little endian on both sides, tag and
   * host side.
   *
   * header is constrained to be 32 bit aligned (a(4)).  The size of header
   * must be less than DT_MAX_HEADER (+ 1) and data length must be less than
   * DT_MAX_DLEN (+ 1).  Data is immediately copied after the header (its
   * contiguous).
   *
   * hlen is the actual size of the header, dlen is the actual size of the
   * data.  hlen + dlen should match what is laid down in header->len.
   *
   * All dblk headers are assumed to start on a 32 bit boundary (aligned(4)).
   *
   * After writing a header/data combination (the whole typed_data block),
   * we align the next potential typed_data block onto a 32 bit boundary.
   * In other words we always keep typed_data blocks aligned in memory as
   * well as on the disk sector.
   *
   * dblk headers are constrained to fit completely into a data sector.  Data
   * immediately follows the dblk header as long as there is space.  Data
   * can flow into as many sectors as needed following the dblk header.
   */
  command void Collect.collect_nots(dt_header_t *header, uint16_t hlen,
                                    uint8_t     *data,   uint16_t dlen) {
    if (dcc.majik_a != DC_MAJIK || dcc.majik_b != DC_MAJIK)
      call Panic.panic(PANIC_SS, 1, dcc.majik_a, dcc.majik_b, 0, 0);
    if ((uint32_t) header & 0x3 || (uint32_t) dcc.cur_ptr & 0x03 ||
        dcc.remaining > SD_BLOCKSIZE)
      call Panic.panic(PANIC_SS, 2, (parg_t) header, (parg_t) dcc.cur_ptr, dcc.remaining, 0);
    if (header->len != (hlen + dlen) ||
        header->dtype > DT_MAX       ||
        hlen > DT_MAX_HEADER         ||
        (hlen + dlen) < 4)
      call Panic.panic(PANIC_SS, 3, hlen, dlen, header->len, header->dtype);

    if (hlen + dlen > DT_MAX_RLEN)
      call Panic.panic(PANIC_SS, 4, (parg_t) data, dlen, 0, 0);

    /* update recnum and calc the checksum */
    finish_record(header, hlen, data, dlen);
    nop();                              /* BRK */
    copy_out((void *)header, hlen);
    copy_out((void *)data,   dlen);
    align_next();
  }


  command void Collect.collect(dt_header_t *header, uint16_t hlen,
                               uint8_t     *data,   uint16_t dlen) {
    call Rtc.getTime(&header->rt);
    call Collect.collect_nots(header, hlen, data, dlen);
  }


  /*
   * buf_offset: return the offset into the current Alloc buffer (if any).
   *
   * whole records get laid down, so at the time of the call to
   * buf_offset, this should always be a record boundary offset.
   *
   * dcc.cur_buf being populated says a buffer is in play.  If not
   * the buf_offset is 0.
   */
  async command uint32_t Collect.buf_offset() {
    atomic {
      if (dcc.cur_buf)
        return SD_BLOCKSIZE - dcc.remaining;
      return 0;
    }
  }


  command void CollectEvent.logEvent(uint16_t ev, uint32_t arg0, uint32_t arg1,
                                                  uint32_t arg2, uint32_t arg3) {
    dt_event_t  e;
    dt_event_t *ep;

    ep = &e;
    ep->len   = sizeof(e);
    ep->dtype = DT_EVENT;
    ep->ev    = ev;
    ep->pcode = 0;
    ep->w     = 0;
    ep->arg0  = arg0;
    ep->arg1  = arg1;
    ep->arg2  = arg2;
    ep->arg3  = arg3;
    call Collect.collect((void *)ep, sizeof(e), NULL, 0);
  }


/*
 * Dblk Record Resync
 *
 * The following provides Collect's resync functionality.  The primary
 * purpose of resync is to find the proper record alignment in the dblk
 * file.  This is sometimes lost or corrupted due to system failures. Other
 * times we just want to jump to an arbitrary position in the file and find
 * the record boundary. The sync record is used as the marker for this
 * alignment since it is laid down in the dblk file on a periodic basis and
 * has a well known format for correctly matching.
 *
 * resyncStart   command to initiate a search for a sync
 *               record starting at the specified offset
 *               in the dblk file. The terminal offset
 *               sets how far to search. If -1 then
 *               search to end of file.
 *
 *               SUCCESS: found result, new offset
 *                        returned
 *               EODATA:  not found within range, (beyond end
 *                        of file or terminal range).
 *               EBUSY:   disk io is in progress, result
 *                        will be signalled when done
 *
 * resyncDone    event to signal completion of search.
 *               returns offset
 *
 * Assumptions
 * - sync records are word aligned
 * - sync records are fixed length
 * - sync records can span across sector boundaries
 * - sync record structure definition is fixed (any
 *   future changes will affect this code)
 * - majik field is last field in sync record structure
 *
 * Algorithm
 * - if already searching, return EBUSY
 * - start a deadman timer
 * - initialize state variables
 * - repeat until sync record found or unrecoverable error:
 *   - call dmf.mapAll() with candidate offset and size of
 *     sync record. It returns success if all data is
 *     available or EBUSY if it needs to retrieve more data.
 *     It signal dmf.data_avail when is data and can now be
 *     accessed
 *   - check buffer to see if sync record is present, look
 *     for majik field, type, length, recsum
 *   - if valid sync record, then signal Collect.resyncDone
 *     and record file offset
 *   - otherwise, increment the offset by 4 bytes and try
 *     again
 * - terminate search and return EODATA when terminal
 *   offset has been exceeded or end of file is detected
 * - return SUCCESS and offset where sync record is located
 *   if sync record is detected
 *
 */

  bool sync_valid(dt_sync_t *sync) {
    uint16_t chksum;
    uint16_t i;
    uint8_t *ptr;

    if (sync->sync_majik != SYNC_MAJIK)
      return FALSE;
    if (sync->dtype != DT_SYNC)
      return FALSE;
    if (sync->len != sizeof(dt_sync_t))
      return FALSE;
    ptr = (uint8_t *) sync;
    for (chksum = 0, i = 0; i < sync->len; i++)
      chksum += ptr[i];
    chksum -= (sync->recsum & 0xff00) >>8;
    chksum -= (sync->recsum & 0xff00);
    if (chksum != sync->recsum)
      return FALSE;
    return TRUE;
  }


  /*
   * core routine for finding sync records
   */
  uint32_t sync_search() {
    dt_sync_t    *sync;
    uint32_t      dlen = sizeof(dt_sync_t);

    scb.err = EODATA;
    while(scb.cur_offset < scb.term_offset) {
      scb.err = call DMF.mapAll(0, (uint8_t **) &sync, scb.cur_offset, &dlen);
      if(scb.err != SUCCESS)
        return 0; /* in case of EBUSY, sync_search is called again */
      if (dlen != sizeof(dt_sync_t) || !sync)
        call Panic.panic(PANIC_SS, 5, dlen, (parg_t) sync, 0,0);
      if (sync_valid(sync))
        return scb.cur_offset;
      scb.cur_offset += sizeof(uint32_t);
    }
    return 0;
  }

  /*
   * start the resync operation.
   */
  command error_t Collect.resyncStart(uint32_t *p_offset, uint32_t term_offset) {

    if (!p_offset)
      call Panic.panic(PANIC_SS, 6, 0,0,0,0);

    if (scb.in_progress) return EBUSY;

    scb.in_progress  = TRUE;
    scb.found_offset = 0;
    scb.cur_offset = *p_offset & ~3;        // quad aligned.
    scb.term_offset = term_offset;
    call ResyncTimer.startOneShot(5000);    // five second deadman timer

    // look for sync record
    scb.found_offset = sync_search();

    if (scb.err == SUCCESS) {
      // found sync, set p_offset to new value
      *p_offset = scb.found_offset;
      call ResyncTimer.stop();
      scb.in_progress = FALSE;
      scb.err = SUCCESS;
    } else if (scb.err != EBUSY) {
      // detected unrecoverable error, terminate search
      *p_offset = -scb.err; // denote error
      call ResyncTimer.stop();
      scb.in_progress = FALSE;
    } // else busy reading next sector, try again later
    return scb.err;
  }

  /* handle signal when new data is available to continue search */
  event void DMF.data_avail(error_t err) {
    if (!scb.in_progress)       /* ignore if not ours */
      return;
    if ((scb.found_offset = sync_search()) || (scb.err != EBUSY)) {
      call ResyncTimer.stop();
      scb.in_progress = FALSE;
      signal Collect.resyncDone(scb.err, scb.found_offset);
    }
  }

  event void ResyncTimer.fired() {
    // deadman timer expired
    call Panic.panic(PANIC_SS, 7, 0,0,0,0);
  }

  event void DMF.extended(uint32_t context, uint32_t offset)  { }
  event void DMF.committed(uint32_t context, uint32_t offset) { }
  default event void Collect.resyncDone(error_t err, uint32_t offset) { }


  async event void SysReboot.shutdown_flush() {
    dt_sync_t  s;
    dt_sync_t *sp;

    nop();                              /* BRK */

    /*
     * System is going down.  We want SSW to flush any pending buffers.
     * This are the FULL buffers and we will let SSW handle them.
     *
     * However, Collect may have a pending (ALLOC'd) buffer.  The buffer is
     * ready to go as is.  But if we have room put one last sync record
     * down that records what we currently think the current rtctime is.
     * Yeah!
     */
    sp = &s;
    if (dcc.cur_buf) {
      /*
       * have a current buffer.  If we have space then add
       * a SYNC record, which will include a time corellator.
       */
      if (dcc.remaining >= sizeof(dt_sync_t)) {
        sp->len        = sizeof(dt_sync_t);
        sp->dtype      = DT_SYNC_FLUSH;
        call Rtc.getTime(&sp->rt);
        sp->sync_majik = SYNC_MAJIK;
        sp->prev_sync  = dcc.last_sync_offset;
        dcc.last_sync_offset = get_rec_offset();

        /* add recnum and checksum the record */
        finish_record( (void *) sp, sizeof(dt_sync_t), NULL, 0);
        copy_block_out((void *) sp, sizeof(dt_sync_t));
      }
      dcc.remaining = 0;
    }
    call SSW.flush_all();
  }

        event void SS.dblk_stream_full()           { }
        event void SS.dblk_advanced(uint32_t last) { }
  async event void Panic.hook()                    { }
}

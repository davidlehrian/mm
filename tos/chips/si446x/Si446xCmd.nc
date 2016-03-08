/**
  * The interface for Si446x Radio Chip Low level access.
  *
  * This interface abstracts the low level radio chip input/output operations
  * into a set of basic commands for controlling chip functionality.
  * Though primarily a set of commands, one event is included to manage the hardware
  * interrupt operation.
  *
  * All access to the SPI interface is performed within this interface, though the
  * acquisition of the arbiter not. It is assumed that the SPI port is dedicated to
  * the radio chip.
  *
  * All access to chip-related MSP hardware (GPIO, etc) is handled within this interface
  * as well and exposed as abstracted commands.
  *
  * @author Dan Maltbie
  * @date   March 1 2016
  */

interface Si446xCmd {
  async command bool          check_CCA();
  async command void          clr_cs();
  async command void          cmd_reply(const uint8_t *cp, uint16_t cl, uint8_t *rp, uint16_t rl);
  async command void          config_frr();
  async command void          disableInterrupt();
  async command void          dump_radio();
  async command void          enableInterrupt();

  /**
    * Get current state of the radio chip using fast read register.
    *
    * @return        device state as read from the fast read register
    */
  async command uint8_t       fast_device_state();

  async command uint8_t       fast_ph_pend();
  async command uint8_t       fast_modem_pend();
  async command uint8_t       fast_latched_rssi();
  async command void          fast_all(uint8_t *status);

  /**
    * Get information about the current tx/rx fifo depths and optionally flush.
    *
    * @param    rxp           pointer to word to return rx fifo count
    * @param    txp           pointer to word to return tx fifo count
    * @param    flush_bits    flags for flushing rx and/or tx fifos
    */
  async command void          fifo_info(uint16_t *rxp, uint16_t *txp, uint8_t flush_bits);

  /**
   * Get a list of configuration lists.
   *
   * Get a list of pointers, each pointing to a list (array) of configuration strings
   * formated appropiately for the send_cmd routine.  This includes a list of the
   * configuration strings generated by the WDS program as well as local configuration
   * specific to the radio driver.
   *
   * @return    a list of configuration string lists (list of list of string)
   */
  async command uint8_t    ** get_config_lists();
  async command bool          get_cts();
  async command uint16_t      get_packet_info();
  async command void          get_reply(uint8_t *r, uint16_t l, uint8_t cmd);
  async command void          goto_ready();
  async event void            interrupt();
  async command void          ll_clr_ints();
  async command void          ll_getclr_ints(volatile si446x_int_state_t *intp);
  async command void          power_up();
  async command void          read_property(uint16_t p_id, uint16_t num, uint8_t *w);
  async command void          read_rx_fifo(uint8_t *data, uint8_t length);
  async command void          set_property(uint16_t prop, uint8_t *values, uint16_t vl);
  async command void          send_cmd(const uint8_t *c, uint8_t *response, uint16_t length);
  async command void          shutdown();
  async command void          start_tx(uint16_t len);
  async command void          start_rx();
  async command void          start_rx_short();
  async command void          trace_radio_pend(uint8_t *pend);
  async command void          unshutdown();
  async command bool          wait_for_cts();
  async command void          write_tx_fifo(uint8_t *data, uint8_t length);
}

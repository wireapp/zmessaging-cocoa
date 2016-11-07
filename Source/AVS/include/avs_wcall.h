/*
 * Wire
 * Copyright (C) 2016 Wire Swiss GmbH
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdlib.h>

struct wcall;

/* Send calling message otr data */
typedef int (wcall_send_h)(const char *convid, const char *userid,
			   const char *clientid,
			   const uint8_t *data, size_t len,
			   void *arg);

/* Incoming call */
typedef void (wcall_incoming_h)(const char *convid, const char *userid,
				struct wcall *call, void *arg);

/* Call established (with media) */
typedef void (wcall_estab_h)(const char *convid, const char *userid,
			     struct wcall *call, void *arg);


#define WCALL_REASON_NORMAL     0
#define WCALL_REASON_ERROR      1
#define WCALL_REASON_TIMEOUT    2
#define WCALL_REASON_LOST_MEDIA 3

/* Call terminated */
typedef void (wcall_close_h)(int reason,
			     const char *convid, const char *userid,
			     struct wcall *call, void *arg);


int wcall_init(const char *userid,
	       const char *clientid,
	       wcall_send_h *sendh,
	       wcall_incoming_h *incomingh,
	       wcall_estab_h *estabh,
	       wcall_close_h *closeh,
	       void *arg);

/* optional, if not called, it will be populated internally
 * from /calls/config
 */
int wcall_set_ice_servers(struct zapi_ice_server *srv,
			  size_t srvc);

/* Returns an opaque call reference, or NULL if we failed to start the call */
struct wcall *wcall_start(const char *convid);

/* Returns an opaque call reference, or NULL if we failed to answer a call */
struct wcall *wcall_answer(const char *convid);

/* An OTR call-type message has been received,
 * msg_time is the backend timestamp of when the message was received
 * curr_time is the timestamp (synced as close as possible)
 * to the backend time when this function is called.
 */
void wcall_recv_msg(const uint8_t *msg, size_t len,
		    uint32_t curr_time, /* timestamp in seconds */
		    uint32_t msg_time,  /* timestamp in seconds */
		    const char *convid,
		    const char *userid,
		    const char *clientid);


/* End the call associated with the opaque call
 * specified in the call parameter.
 * The opaque call object is typically acquired by calling either:
 * wcall_start or wcall_answer.
 */
void wcall_end(struct wcall *call);

/* End the call in the conversation associated to 
 * the conversation id in the convid parameter.
 */
void wcall_end_inconv(const char *convid);

void wcall_close(void);

int  wcall_debug(struct re_printf *pf, void *ignored);


#define WCALL_STATE_NONE        0 /* There is no call */
#define WCALL_STATE_OUTGOING    1 /* Outgoing call is pending */ 
#define WCALL_STATE_INCOMING    2 /* Incoming call is pending */
#define WCALL_STATE_ESTABLISHED 3 /* Established call */
#define WCALL_STATE_TERMINATING 4 /* In process of being terminated */
#define WCALL_STATE_UNKNOWN     5 /* Unknown */

int  wcall_get_state(struct wcall *call);
int  wcall_get_state_inconv(const char *convid);

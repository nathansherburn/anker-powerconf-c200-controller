#ifndef CUVC_H
#define CUVC_H

#include <stdbool.h>
#include <stdint.h>

// Minimal UVC control transport over IOKit. Class requests go to the device's
// default control pipe, so no interface needs to be claimed and the macOS UVC
// driver (and any app streaming from the camera) keeps working alongside us.

typedef struct cuvc_device cuvc_device;

// Opens the first USB device matching vid/pid. Returns NULL if none is attached.
cuvc_device *cuvc_open(uint16_t vid, uint16_t pid);
void cuvc_close(cuvc_device *dev);

// GET_* request (request = 0x81 GET_CUR ... 0x87 GET_DEF). Returns bytes read, or -1.
int cuvc_get(cuvc_device *dev, uint8_t request, uint8_t unit, uint8_t selector,
             uint8_t interface, void *buf, uint16_t len);

// SET_CUR request. Returns 0 on success, -1 on failure.
int cuvc_set(cuvc_device *dev, uint8_t unit, uint8_t selector, uint8_t interface,
             const void *buf, uint16_t len);

// Copies the active configuration descriptor into buf. Returns bytes copied, or -1.
int cuvc_config_descriptor(cuvc_device *dev, void *buf, int maxlen);

// Calls cb on the main run loop whenever a matching device is attached or removed.
// Devices already present when watching starts do not trigger a callback.
typedef void (*cuvc_hotplug_cb)(void *ctx, bool attached);
bool cuvc_watch(uint16_t vid, uint16_t pid, cuvc_hotplug_cb cb, void *ctx);

#endif

#include "cuvc.h"

#include <stdlib.h>
#include <string.h>

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>

struct cuvc_device {
    IOUSBDeviceInterface182 **dev;
};

static CFMutableDictionaryRef matching_dict(uint16_t vid, uint16_t pid) {
    CFMutableDictionaryRef match = IOServiceMatching("IOUSBHostDevice");
    int v = vid, p = pid;
    CFNumberRef nv = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &v);
    CFNumberRef np = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &p);
    CFDictionarySetValue(match, CFSTR(kUSBVendorID), nv);
    CFDictionarySetValue(match, CFSTR(kUSBProductID), np);
    CFRelease(nv);
    CFRelease(np);
    return match;
}

cuvc_device *cuvc_open(uint16_t vid, uint16_t pid) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, matching_dict(vid, pid));
    if (!service) return NULL;

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(
        service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS || !plugin) return NULL;

    IOUSBDeviceInterface182 **dev = NULL;
    HRESULT hr = (*plugin)->QueryInterface(
        plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID182), (LPVOID *)&dev);
    IODestroyPlugInInterface(plugin);
    if (hr != S_OK || !dev) return NULL;

    cuvc_device *d = calloc(1, sizeof(*d));
    d->dev = dev;
    return d;
}

void cuvc_close(cuvc_device *d) {
    if (!d) return;
    (*d->dev)->Release(d->dev);
    free(d);
}

static int control_request(cuvc_device *d, uint8_t type, uint8_t request, uint16_t value,
                           uint16_t index, void *buf, uint16_t len) {
    IOUSBDevRequestTO req = {
        .bmRequestType = type,
        .bRequest = request,
        .wValue = value,
        .wIndex = index,
        .wLength = len,
        .pData = buf,
        .noDataTimeout = 500,
        .completionTimeout = 1000,
    };
    if ((*d->dev)->DeviceRequestTO(d->dev, &req) != kIOReturnSuccess) return -1;
    return (int)req.wLenDone;
}

int cuvc_get(cuvc_device *d, uint8_t request, uint8_t unit, uint8_t selector,
             uint8_t interface, void *buf, uint16_t len) {
    // Class-specific, interface recipient, device-to-host.
    return control_request(d, 0xA1, request, (uint16_t)(selector << 8),
                           (uint16_t)(unit << 8 | interface), buf, len);
}

int cuvc_set(cuvc_device *d, uint8_t unit, uint8_t selector, uint8_t interface,
             const void *buf, uint16_t len) {
    // Class-specific, interface recipient, host-to-device; 0x01 = SET_CUR.
    int n = control_request(d, 0x21, 0x01, (uint16_t)(selector << 8),
                            (uint16_t)(unit << 8 | interface), (void *)buf, len);
    return n < 0 ? -1 : 0;
}

int cuvc_config_descriptor(cuvc_device *d, void *buf, int maxlen) {
    IOUSBConfigurationDescriptorPtr config = NULL;
    if ((*d->dev)->GetConfigurationDescriptorPtr(d->dev, 0, &config) != kIOReturnSuccess || !config)
        return -1;
    int total = USBToHostWord(config->wTotalLength);
    int n = total < maxlen ? total : maxlen;
    memcpy(buf, config, (size_t)n);
    return n;
}

typedef struct {
    cuvc_hotplug_cb cb;
    void *ctx;
} watch_ctx;

static bool drain(io_iterator_t it) {
    bool any = false;
    io_service_t s;
    while ((s = IOIteratorNext(it))) {
        any = true;
        IOObjectRelease(s);
    }
    return any;
}

static void on_attached(void *refcon, io_iterator_t it) {
    watch_ctx *w = refcon;
    if (drain(it)) w->cb(w->ctx, true);
}

static void on_removed(void *refcon, io_iterator_t it) {
    watch_ctx *w = refcon;
    if (drain(it)) w->cb(w->ctx, false);
}

bool cuvc_watch(uint16_t vid, uint16_t pid, cuvc_hotplug_cb cb, void *ctx) {
    IONotificationPortRef port = IONotificationPortCreate(kIOMainPortDefault);
    if (!port) return false;
    CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port),
                       kCFRunLoopDefaultMode);

    // Lives for the rest of the process, like the notification port.
    watch_ctx *w = malloc(sizeof(*w));
    w->cb = cb;
    w->ctx = ctx;

    io_iterator_t added = 0, removed = 0;
    if (IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching_dict(vid, pid),
                                         on_attached, w, &added) != KERN_SUCCESS)
        return false;
    if (IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching_dict(vid, pid),
                                         on_removed, w, &removed) != KERN_SUCCESS)
        return false;

    // Draining arms the notifications; existing devices are deliberately not reported.
    drain(added);
    drain(removed);
    return true;
}

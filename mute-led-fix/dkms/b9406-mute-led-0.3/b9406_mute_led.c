// SPDX-License-Identifier: GPL-2.0-only
/* B9406CAA firmware exposes the speaker mute LED via ASUS WMI 0x4001c.
 * Only adds the missing LED; the stock driver owns platform::micmute.
 */
#include <linux/module.h>
#include <linux/dmi.h>
#include <linux/leds.h>
#include <linux/platform_data/x86/asus-wmi.h>

#define SPEAKER_MUTE_LED 0x0004001c

static int mute_set(struct led_classdev *led, enum led_brightness value)
{
	u32 result;
	int ret = asus_wmi_set_devstate(SPEAKER_MUTE_LED, !!value, &result);
	return ret ? ret : (result == 1 ? 0 : -EIO);
}

static enum led_brightness mute_get(struct led_classdev *led)
{
	u32 state;
	if (asus_wmi_get_devstate_dsts(SPEAKER_MUTE_LED, &state))
		return led->brightness;
	return (state & ASUS_WMI_DSTS_STATUS_BIT) ? LED_ON : LED_OFF;
}

static struct led_classdev mute_led = {
	.name = "platform::mute",
	.max_brightness = 1,
	.brightness_set_blocking = mute_set,
	.brightness_get = mute_get,
	.default_trigger = "audio-mute",
	.flags = LED_RETAIN_AT_SHUTDOWN,
};

static int __init b9406_mute_init(void)
{
	u32 state;
	int ret;
	if (!dmi_match(DMI_PRODUCT_NAME, "ASUS EXPERTBOOK B9406CAA"))
		return -ENODEV;
	ret = asus_wmi_get_devstate_dsts(SPEAKER_MUTE_LED, &state);
	if (ret)
		return ret;
	if (!(state & ASUS_WMI_DSTS_PRESENCE_BIT))
		return -ENODEV;
	/* Yield to a future native driver instead of registering a renamed LED. */
	mute_led.flags |= LED_REJECT_NAME_CONFLICT;
	mute_led.brightness = !!(state & ASUS_WMI_DSTS_STATUS_BIT);
	return led_classdev_register(NULL, &mute_led);
}

static void __exit b9406_mute_exit(void)
{
	led_classdev_unregister(&mute_led);
}
module_init(b9406_mute_init);
module_exit(b9406_mute_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("ASUS ExpertBook B9406CAA speaker mute LED");
MODULE_IMPORT_NS("ASUS_WMI");

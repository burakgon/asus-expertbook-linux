obj-m += snd-soc-sof-sdw.o
snd-soc-sof-sdw-y := sof_sdw.o sof_sdw_hdmi.o

# Linux 7.3 changed asoc_sdw_parse_sdw_endpoints() to take (dev, ctx) instead
# of the card, and stable backported that to 7.2.8. Probe the target kernel's
# header rather than its version so any stable/distro backport builds. The
# regex lives in a variable because make would count its "(" in $(shell ...).
parse_dev_ctx := asoc_sdw_parse_sdw_endpoints\([[:space:]]*struct device
ifneq ($(shell grep -Eqs '$(parse_dev_ctx)' $(srctree)/include/sound/soc_sdw_utils.h && echo y),)
ccflags-y += -DSOF_SDW_PARSE_DEV_CTX
endif

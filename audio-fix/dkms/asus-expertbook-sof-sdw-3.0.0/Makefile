obj-m += snd-soc-sof-sdw.o
snd-soc-sof-sdw-y := sof_sdw.o sof_sdw_hdmi.o

# Linux 7.2.4+ changed asoc_sdw_parse_sdw_endpoints from
#   struct snd_soc_card *card, soc_aux, soc_dais, soc_ends, num_devs   -> 5 args
# to
#   struct device *dev, struct asoc_sdw_mc_private *ctx, ...           -> 6 args
#
# Probe the installed header rather than testing LINUX_VERSION_CODE: this API
# can move in a stable point release without the version number telling you so,
# and when the build breaks DKMS fails silently during a system update.
#
# NOTE: the grep pattern must contain no literal parenthesis -- make counts
# parens inside $(shell ...) even when they are quoted, and a bare '(' gives
# "unterminated call to function 'shell'". The '.' matches it instead.
SDW_UTILS_H := /lib/modules/$(KERNELRELEASE)/build/include/sound/soc_sdw_utils.h
SDW_NEW_API := $(shell grep -qE 'asoc_sdw_parse_sdw_endpoints.struct device' $(SDW_UTILS_H) 2>/dev/null && echo -DHAVE_ASOC_SDW_PARSE_DEV_CTX=1)
ccflags-y += $(SDW_NEW_API)

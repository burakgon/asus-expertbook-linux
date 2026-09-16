obj-m += snd-soc-sof-sdw.o
snd-soc-sof-sdw-y := sof_sdw.o sof_sdw_hdmi.o

# asoc_sdw_parse_sdw_endpoints() gained explicit dev/ctx parameters in some
# kernel builds after the last time this file was refreshed against upstream
# (compiles fine against 7.2.3-arch1-3's header, fails against
# 7.2.5-3-omarchy's). Probe the actual installed header instead of guessing a
# version boundary, since this is a rolling kernel where the exact commit that
# landed the change isn't known.
ccflags-y += $(shell grep -A2 'int asoc_sdw_parse_sdw_endpoints' \
	$(srctree)/include/sound/soc_sdw_utils.h 2>/dev/null | \
	grep -q 'asoc_sdw_mc_private' && echo -DASOC_SDW_PARSE_ENDPOINTS_6ARG)

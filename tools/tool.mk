# The folders of a tool build, included by every tools/<name>/Makefile before its rules.
#
#   ST_OBJ_DIR  the folder of libst.a and st.h
#   BIN_DIR     the folder the tool binary is built in
#
# When the environment or the command line sets TARGETDIR of ../Makefile, as auto/qemu.sh does, the library is in
# that folder, relative to the ST root, and the tool is built in its tools/<name>, so builds for several CPUs can
# run at once in one checkout. Otherwise the library is in obj, and the tool is built in tools/<name>.
ifdef TARGETDIR
ST_OBJ_DIR  = ../../$(TARGETDIR)
BIN_DIR     = $(ST_OBJ_DIR)/tools/$(notdir $(CURDIR))
$(shell mkdir -p $(BIN_DIR))
else
ST_OBJ_DIR  = ../../obj
BIN_DIR     = .
endif

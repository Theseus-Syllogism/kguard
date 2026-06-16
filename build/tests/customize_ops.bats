load helper

@test "bc_customize copies the provisioner tree in and runs it" {
  source "$BUILD_ROOT/lib/build-common.sh"
  BUILD_DRY_RUN= bc_customize "$(bc_out_image)"
  grep -q "virt-customize" "$MOCK_LOG"
  grep -q -- "--copy-in" "$MOCK_LOG"
  grep -q "guest" "$MOCK_LOG"
  grep -q -- "--run-command" "$MOCK_LOG"
  grep -q "provision.sh" "$MOCK_LOG"
  grep -q -- "-a $(bc_out_image)" "$MOCK_LOG"
}

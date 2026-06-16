load helper

@test "bc_write_manifest emits JSON with versions + image sha256" {
  source "$BUILD_ROOT/lib/build-common.sh"
  : > "$(bc_out_image)"
  BUILD_DRY_RUN= bc_write_manifest
  m="$(bc_manifest_path)"; [ -f "$m" ]
  grep -q '"suricata_version": "8.0.4"' "$m"
  grep -q '"guard_version"' "$m"
  grep -q '"image_sha256"' "$m"
  grep -q '"kicksecure_image_url"' "$m"
}

# Gap #5 (RUNTIME-FINDINGS-2026-06-06): kicksecure_image_url is only the *configured* download URL
# (a placeholder when the operator stages a base image by hand, e.g. a separately-built Kicksecure-CLI
# image). The manifest must also pin the *actual* staged base image by sha256 so provenance is
# verifiable regardless of where the base came from.
@test "manifest pins the actual staged base image by sha256 (verifiable provenance)" {
  source "$BUILD_ROOT/lib/build-common.sh"
  : > "$(bc_out_image)"
  printf 'STAGED-BASE-IMAGE' > "$(bc_stock_image)"
  BUILD_DRY_RUN= bc_write_manifest
  m="$(bc_manifest_path)"
  grep -q "\"base_image\": \"$(basename "$(bc_stock_image)")\"" "$m"
  # the digest must be derived from the staged stock image (not a hardcoded/placeholder value)
  bsha="$(sha256sum "$(bc_stock_image)" | awk '{print $1}')"
  grep -q "\"base_image_sha256\": \"$bsha\"" "$m"
}

module otel

import v.vmod

fn test_version_matches_v_mod() {
	manifest := vmod.decode(@VMOD_FILE)!
	assert manifest.name == 'otel'
	assert version == manifest.version
}

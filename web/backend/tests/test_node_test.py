def test_normalize_arch():
    from kubefoundry.installer.node_test import normalize_arch

    assert normalize_arch("x86_64") == "amd64"
    assert normalize_arch("aarch64") == "arm64"
    assert normalize_arch("loongarch64") == "loongarch64"


def test_parse_os_release():
    from kubefoundry.installer.node_test import parse_os_release

    info = parse_os_release('ID="kylin"\nNAME="Kylin Linux"\nVERSION_ID="V10"\n')
    assert info["os_type"] == "kylin"
    assert info["os_name"] == "Kylin Linux"
    assert info["os_version"] == "V10"
    assert info["os_major"] == "V10"

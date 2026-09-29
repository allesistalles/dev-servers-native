import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("configure_updates", Path(__file__).with_name("configure-updates.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleaseConfigurationTests(unittest.TestCase):
    def test_release_sets_versions_and_drops_sparkle_keys(self):
        info = module.configure(
            {"SUFeedURL": "https://example.com/updates/appcast.xml", "SUPublicEDKey": "abc"},
            {"WTP_VERSION": "2.5", "WTP_BUILD": "9"},
        )
        self.assertNotIn("SUFeedURL", info)
        self.assertNotIn("SUPublicEDKey", info)
        self.assertEqual(info["CFBundleShortVersionString"], "2.5")
        self.assertEqual(info["CFBundleVersion"], "9")

    def test_unconfigured_local_build_preserves_metadata(self):
        self.assertEqual(module.configure({"CFBundleVersion": "3"}, {}), {"CFBundleVersion": "3"})

    def test_keeps_local_network_privacy_keys(self):
        info = module.configure({
            "NSLocalNetworkUsageDescription": "Dev Servers finds web portals and devices on your local network.",
            "NSBonjourServices": ["_http._tcp", "_arduino._tcp"],
        }, {})
        self.assertEqual(info["NSLocalNetworkUsageDescription"], "Dev Servers finds web portals and devices on your local network.")
        self.assertEqual(info["NSBonjourServices"], ["_http._tcp", "_arduino._tcp"])

    def test_host_app_version_does_not_override_bundle_version(self):
        info = {"CFBundleShortVersionString": "2.1", "CFBundleVersion": "3"}
        self.assertEqual(module.configure(dict(info), {"APP_VERSION": "0.87.3", "APP_BUILD": "999"}), info)

    def test_rejects_invalid_versions(self):
        for value in ["../4", "v2.2", "4-beta", "4/5"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.configure({}, {"WTP_BUILD": value})


if __name__ == "__main__":
    unittest.main()

import importlib
import logging
import unittest
from unittest.mock import patch

from launchpadlib.launchpad import Launchpad


class TestBugBind(unittest.TestCase):
    def setUp(self):
        self.bugbind = importlib.import_module("bug-bind")
        # do not mess around production.
        self.bugbind.SERVICE_ROOT = "staging"
        self.bugbind.lp = Launchpad.login_anonymously(self.bugbind.APP_NAME, service_root=self.bugbind.SERVICE_ROOT, version='1.0')
        self.bugbind.log.setLevel(logging.DEBUG)
        pass

    def tearDown(self):
        self.bugbind = None
        pass

    def test_bugformat(self):
        with self.assertRaises(AssertionError) as content:
            self.bugbind.link_bugs("NOT A BUG NUMBER", [], "swe")
        with self.assertRaises(AssertionError) as content:
            self.bugbind.link_bugs("1", ["NOT A BUG NUMBER"], "swe")


    @patch('lazr.restfulclient.resource.Entry.lp_save')
    @patch('lazr.restfulclient.resource.NamedOperation')
    def test_linkbugs(self, mock_op, mock_lp_save):
        self.bugbind.link_bugs("1000", ["46081"], "swe")
        # TODO: not able to see the description of private bug changed, lp_save does not pass anything.
        mock_op.assert_called()
        assert('oem-priority' in mock_op.call_args.args[1].tags)
        assert('originate-from-46081' in mock_op.call_args.args[1].tags)

if __name__ == '__main__':
    unittest.main()

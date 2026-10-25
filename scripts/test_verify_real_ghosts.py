#!/usr/bin/env python3
"""Expected-status boundaries for the real-ghost verification harness."""
import unittest
from verify_real_ghosts import expected_status_rules, status_verdict


class ExpectedStatusTests(unittest.TestCase):
    def setUp(self):
        self.rule = {'event': 'OnDestroy', 'method': 'NOTIFY', 'status': 400,
                     'reason': 'Test dictionary explicitly rejects its undefined event'}
        self.rules = expected_status_rules({'expected_statuses': [self.rule]})

    def verdict(self, event='OnDestroy', method='NOTIFY', status=400, rules=None, cmd='request'):
        return status_verdict({'cmd': cmd, 'id': event, 'method': method}, {'status': status},
                              self.rules if rules is None else rules)['status_matches']

    def test_default_rejects_error_status(self):
        self.assertFalse(self.verdict(rules={}))
        self.assertTrue(self.verdict(status=204, rules={}))
        self.assertFalse(self.verdict(status=None, rules={}))

    def test_exception_is_exact_event_and_method(self):
        self.assertTrue(self.verdict())
        self.assertFalse(self.verdict(event='OnBoot'))
        self.assertFalse(self.verdict(method='GET'))
        self.assertFalse(self.verdict(cmd='load'))

    def test_expected_status_does_not_allow_other_statuses(self):
        self.assertFalse(self.verdict(status=500))
        self.assertFalse(self.verdict(status=204))

    def test_reason_and_non_wildcard_target_are_required(self):
        for changes in [{'reason': ''}, {'event': '*'}, {'method': '*'}, {'status': '400'}]:
            with self.assertRaises(ValueError):
                expected_status_rules({'expected_statuses': [{**self.rule, **changes}]})

    def test_duplicate_rules_are_rejected(self):
        with self.assertRaises(ValueError):
            expected_status_rules({'expected_statuses': [self.rule, self.rule]})


if __name__ == '__main__':
    unittest.main()

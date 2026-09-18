import json
import gc
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from api.detection_server import create_server
from security.models import Confidence, RuleType, SecurityRule, Severity
from security.repository import SecurityRepository


class DetectionServerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        directory = Path(self.temp.name)
        self.repository = SecurityRepository(str(directory / 'test.db'))
        self.repository.save_rule(SecurityRule('SIG-TEST-001', 'Test', RuleType.SIGNATURE,
            'marker', Severity.HIGH, Confidence.HIGH, 'Test', 'Test'))
        (directory / 'active_security_library.json').write_text('{"Version":"test"}')
        self.server = create_server(port=0, database=directory / 'test.db', directory=directory)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}'

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        # Existing repository connections are released by GC after transactions.
        gc.collect()
        self.temp.cleanup()

    def post(self, payload):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        request = Request(self.url + '/detections', data=body, headers={'Content-Type': 'application/json'})
        try:
            response = urlopen(request, timeout=5)
        except HTTPError as error:
            response = error
        with response:
            return response.status, json.loads(response.read())

    def test_counts_and_unknown_rule(self):
        status, body = self.post({'detections': [
            {'ruleId': 'SIG-TEST-001', 'count': 3}, {'ruleId': 'unknown', 'count': 2}]})
        self.assertEqual((status, body), (200, {'accepted': 1, 'unknown': 1}))
        self.assertEqual(self.repository.get_detection_count('SIG-TEST-001'), 3)
        self.post({'detections': [{'ruleId': 'SIG-TEST-001', 'count': 2}]})
        self.assertEqual(self.repository.get_detection_count('SIG-TEST-001'), 5)

    def test_malformed_requests_do_not_increment(self):
        invalid = [None, [], {}, {'detections': {}}, b'{',
            {'detections': [], 'Source': 'must not be accepted'}]
        entries = [None, {}, {'ruleId': '', 'count': 1}, {'ruleId': '  ', 'count': 1},
            {'ruleId': 4, 'count': 1}, {'ruleId': 'SIG-TEST-001', 'count': True},
            {'ruleId': 'SIG-TEST-001', 'count': 1.5}, {'ruleId': 'SIG-TEST-001', 'count': 0},
            {'ruleId': 'SIG-TEST-001', 'count': -1}, {'ruleId': 'SIG-TEST-001', 'count': 2**64},
            {'ruleId': 'SIG-TEST-001', 'count': 1, 'Source': 'rejected'}]
        invalid.extend({'detections': [{'ruleId': 'SIG-TEST-001', 'count': 1}, entry]} for entry in entries)
        for payload in invalid:
            with self.subTest(payload=payload):
                self.assertEqual(self.post(payload)[0], 400)
        self.assertEqual(self.repository.get_detection_count('SIG-TEST-001'), 0)

    def test_library_url_preserved_and_database_not_served(self):
        with urlopen(self.url + '/active_security_library.json') as response:
            self.assertEqual(json.load(response), {'Version': 'test'})
        with self.assertRaises(HTTPError) as error:
            urlopen(self.url + '/test.db')
        self.assertEqual(error.exception.code, 404)


if __name__ == '__main__':
    unittest.main()

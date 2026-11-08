"""Exercise failure cases that must never be mistaken for a successful Reader demonstration."""
import base64
import contextlib
import importlib.util
import io
import json
import unittest
from pathlib import Path
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('identity_probe',Path(__file__).with_name('identity-probe.py'))
probe=importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

class ReaderBoundaryTests(unittest.TestCase):
    """Use synthetic tokens and responses; tests must never access Azure or log token text."""
    def exercise(self, responses, token_tenant='test-tenant'):
        claims=base64.urlsafe_b64encode(json.dumps({'tid':token_tenant,'oid':'test-principal','aud':'https://management.core.windows.net/'}).encode()).decode().rstrip('=')
        token='synthetic.'+claims+'.not-a-signature'
        calls=[(200,{'access_token':token}),(200,{'tags':{'course':'SC500'}})]+responses
        output=io.StringIO()
        with patch.dict(probe.os.environ,{'TARGET_GROUP_ID':'/subscriptions/test/resourceGroups/rg-sc500-l02-target','EXPECTED_TENANT_ID':'test-tenant'}),patch.object(probe,'request_json',side_effect=calls) as request,contextlib.redirect_stdout(output):
            failure=None
            try:probe.run_probe('system-assigned')
            except RuntimeError as error:failure=error
        self.assertNotIn(token,output.getvalue())
        return failure,request,output.getvalue()

    def test_reader_rejection_is_a_pass(self):
        failure,request,output=self.exercise([(403,{'error':{'code':'AuthorizationFailed'}})])
        self.assertIsNone(failure)
        self.assertIn('"passed": true',output)
        self.assertEqual(request.call_count,3)

    def test_other_403_is_not_rbac_proof(self):
        failure,_,output=self.exercise([(403,{'error':{'code':'RequestDisallowedByPolicy'}})])
        self.assertIsNotNone(failure)
        self.assertIn('"passed": false',output)

    def test_unexpected_write_attempts_only_marker_cleanup(self):
        failure,request,output=self.exercise([(200,{}),(200,{})])
        self.assertIsNotNone(failure)
        self.assertEqual(request.call_args.kwargs['body'],{'operation':'Delete','properties':{'tags':{'sc500-l02-authorization-probe':'denied-expected'}}})
        self.assertIn('"unexpectedWriteCleanupStatus": 200',output)

    def test_wrong_tenant_never_reaches_arm(self):
        failure,request,_=self.exercise([],token_tenant='unexpected-tenant')
        self.assertIsNotNone(failure)
        self.assertEqual(request.call_count,1)

if __name__=='__main__':unittest.main()

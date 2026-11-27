import unittest
from unittest.mock import patch, MagicMock
import keo_pancake as sync


class IncrementalTests(unittest.TestCase):
    def test_last_ad_uses_interaction_time_not_array_order(self):
        self.assertEqual(sync.ad_id_cuoi({'ads':[
            {'ad_id':'latest','inserted_at':'2026-11-27T10:00:00'},
            {'ad_id':'old','inserted_at':'2026-11-26T10:00:00'}]}),'latest')

    def test_tag_order_does_not_trigger_rewrite(self):
        self.assertEqual(sync.dau_van_tag({'tags':[{'id':1},{'id':2}]}),
                         sync.dau_van_tag({'tags':[{'id':2},{'id':1}]}))

    def test_add_remove_preserve_source_timestamps(self):
        rows = sync.tach_lich_su_tag('p',{'id':'c','tag_histories':[
            {'inserted_at':'2026-11-25T01:00:00','payload':{'tag':{'text':'BOOKING'},'action':'add'}},
            {'inserted_at':'2026-11-26T02:00:00','payload':{'tag':{'text':'BOOKING'},'action':'remove'}}]})
        self.assertEqual([r[4] for r in rows],['add','remove'])
        self.assertEqual(rows[0][3].isoformat(),'2026-11-25T01:00:00+00:00')

    def test_chat_only_update_skips_database_write(self):
        old = {'id':'c','tags':[{'id':1}],'ad_ids':['a'],'updated_at':'2026-11-26T01:00:00'}
        db = MagicMock()
        db.cursor.return_value.__enter__.return_value.fetchall.return_value=[('c',old)]
        with patch.object(sync.psycopg2.extras,'execute_values') as writer:
            counts=sync.ghi_hoi_thoai(db,'p','page',[{**old,'updated_at':'2026-11-27T01:00:00'}])
        self.assertEqual(counts,(0,0,0,1))
        writer.assert_not_called()

    def test_tag_and_last_ad_change_count_once_per_conversation(self):
        db = MagicMock()
        old={'id':'c','tags':[],'ad_ids':['a']}
        db.cursor.return_value.__enter__.return_value.fetchall.return_value=[('c',old)]
        with patch.object(sync.psycopg2.extras,'execute_values') as writer:
            counts=sync.ghi_hoi_thoai(db,'p','page',[{'id':'c','tags':[{'id':2}],'ad_ids':['b']}])
        self.assertEqual(counts,(0,1,1,0))
        self.assertEqual(len(writer.call_args.args[2]),1)

    def test_token_error_is_not_empty_success(self):
        r=MagicMock(status_code=200)
        r.json.return_value={'success':False,'conversations':[],'message':'access_token renewed'}
        with patch.object(sync.requests,'get',return_value=r) as get:
            with self.assertRaises(PermissionError):
                sync.lay_mot_page('p','secret',1,2)
        self.assertEqual(get.call_count,1)

    def test_zero_updates_is_valid_and_response_is_projected(self):
        r=MagicMock(status_code=200)
        r.json.return_value={'success':True,'conversations':[]}
        with patch.object(sync.requests,'get',return_value=r) as get:
            self.assertEqual(sync.lay_mot_page('p','secret',1,2),[])
        self.assertNotIn('recent_phone_numbers',get.call_args.kwargs['params']['fields'])
        self.assertIn('tag_histories',get.call_args.kwargs['params']['fields'])


if __name__ == '__main__':
    unittest.main()

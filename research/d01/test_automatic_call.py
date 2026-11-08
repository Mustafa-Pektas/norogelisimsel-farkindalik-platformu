from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace as N
import unittest
from automatic_call import normalize,evaluate_words,detect_call,effective_timing


def segment(words):return N(words=words,no_speech_prob=.01,avg_logprob=-.2)
def word(name='Deniz!',a=.4,b=1.1,p=.95):return N(word=name,start=a,end=b,probability=p)


class AudioTests(unittest.TestCase):
    def test_same_turkish_exact_name_normalisation(self):
        self.assertEqual(normalize(' DENİZ! '),'deniz')
        r=evaluate_words([segment([word()])],7)
        self.assertEqual((r['status'],r['startS'],r['endS']),('accepted',.4,1.1))
    def test_missing_ambiguous_low_confidence_do_not_create_times(self):
        for words,status in [([word('Denizli')],'not_found'),([word(),word()],'ambiguous'),([word(p=.79)],'low_confidence'),([word(b=9)],'low_confidence')]:
            r=evaluate_words([segment(words)],7)
            self.assertEqual(r['status'],status);self.assertIsNone(r['startS']);self.assertIsNone(r['endS'])
    def test_local_only_and_generator_failure_is_nonfatal(self):
        with TemporaryDirectory() as root:
            path=Path(root)
            for f in ('model.bin','config.json','tokenizer.json','preprocessor_config.json'):(path/f).touch()
            def factory(*args,**kw):
                self.assertTrue(kw['local_files_only'])
                class Model:
                    def transcribe(self,*a,**k):
                        def broken():raise RuntimeError('controlled');yield None
                        return broken(),None
                return Model()
            self.assertEqual(detect_call('video',path,7,factory)['status'],'failed')
        self.assertEqual(detect_call('video',None,7)['status'],'unavailable')
    def test_manual_precedence_and_unknown_stays_null(self):
        audio=evaluate_words([],7)
        self.assertEqual(effective_timing(audio,.2,.8)['source'],'manual_user_input')
        self.assertIsNone(effective_timing(audio,None,None)['startS'])


if __name__=='__main__':unittest.main()

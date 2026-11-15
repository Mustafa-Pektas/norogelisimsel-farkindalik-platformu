"""Run: python analyze.py --config config/deniz.json --output outputs/deniz_01"""
import argparse
import json
import sys
from pathlib import Path


def main():
    parser=argparse.ArgumentParser(description="Çağrı sonrası baş ve hedef yönelimi araştırma prototipi")
    root=Path(__file__).resolve().parent
    parser.add_argument("--config",type=Path,default=root/"config"/"deniz.json")
    parser.add_argument("--video",help="Video yolu; verilmezse config ve ardından aynı videonun paket kopyası kullanılır")
    parser.add_argument("--output",type=Path,default=root/"outputs"/"deniz_01")
    parser.add_argument("--no-gaze",action="store_true",help="Yalnızca baş ölçümü; hedef/tepki sonucu değerlendirilemeyebilir")
    args=parser.parse_args()
    try:
        from sesyon.pipeline import run,resolve_video
        config=json.loads(args.config.read_text(encoding="utf-8-sig"))
        source=resolve_video(config,args.video,root)
        result=run(config,source,args.output,not args.no_gaze)
        for event in result["events"]:
            print(event["label_tr"])
        return 0
    except (ValueError,RuntimeError,ImportError,OSError) as exc:
        print("HATA: "+str(exc),file=sys.stderr)
        print("Ayrıntılı hata kaydı için: python -X faulthandler analyze.py ...",file=sys.stderr)
        return 1


if __name__=="__main__":
    sys.exit(main())

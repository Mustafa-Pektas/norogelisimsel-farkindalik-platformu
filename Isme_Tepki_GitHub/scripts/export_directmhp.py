"""Resmî DirectMHP-S CMU-HPE ağırlığını analizde kullanılan biçime aktarır."""
import argparse
import hashlib
import json
from pathlib import Path
import sys


REVISION = 'a51b06bc34ed4202a9e9d1aad1c1cac9b6de05d0'
CHECKPOINT_SHA256 = '5c59bb4689a340c14ebe575b58f852eb9b5c18d5b9b813c88a48cf6d5385b72e'


def export(upstream, weights, output):
    if hashlib.sha256(weights.read_bytes()).hexdigest() != CHECKPOINT_SHA256:
        raise ValueError('DirectMHP-S CMU-HPE ağırlığının SHA-256 değeri uyuşmuyor.')
    if not (upstream / 'models/yolo.py').is_file():
        raise ValueError('Resmî DirectMHP kaynak klasörünü --source ile belirtin.')
    if output.exists():
        raise FileExistsError(f'Çıktı zaten var: {output}')

    import numpy as np
    import torch

    sys.path.insert(0, str(upstream))
    from models.common import Bottleneck, C3, Concat, Conv, Focus, SPP
    from models.yolo import Detect, Model

    torch.set_num_threads(min(torch.get_num_threads(), 4))
    nn = torch.nn
    allowed = [Model, Detect, Conv, C3, Bottleneck, Concat, Focus, SPP, nn.Conv2d, nn.SiLU,
               nn.BatchNorm2d, nn.MaxPool2d, nn.Upsample, nn.ModuleList, nn.Sequential,
               np.core.multiarray._reconstruct, np.ndarray, np.dtype, np.dtypes.Float64DType,
               np.dtypes.Float32DType, np.dtypes.Int64DType, np.dtypes.Int32DType]
    with torch.serialization.safe_globals(allowed):
        saved = torch.load(weights, map_location='cpu', weights_only=True)
    network = (saved.get('ema') or saved['model']).float().fuse().eval()
    network.model[-1].inplace = False

    class Inference(nn.Module):
        def __init__(self, model):
            super().__init__()
            self.model = model

        def forward(self, images):
            return self.model(images)[0]

    wrapper = Inference(network).eval()
    height, width = 768, 1280
    torch.manual_seed(27)
    example = torch.rand(1, 3, height, width)
    with torch.no_grad():
        expected = wrapper(example)
        traced = torch.jit.freeze(torch.jit.trace(wrapper, example))
        observed = traced(example)
        torch.testing.assert_close(observed, expected, atol=.002, rtol=.0001)
        if observed.ndim != 3 or observed.shape[2] != 9:
            raise ValueError(f'Beklenmeyen DirectMHP çıktı biçimi: {tuple(observed.shape)}')

    metadata = dict(model='DirectMHP-S CMU-HPE', input_hw=[height, width],
                    revision=REVISION, checkpoint_sha256=CHECKPOINT_SHA256)
    output.parent.mkdir(parents=True, exist_ok=True)
    torch.jit.save(traced, str(output), _extra_files={'directmhp.json': json.dumps(metadata)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True,
                        help=f'Resmî DirectMHP kaynak klasörü ({REVISION})')
    parser.add_argument('--weights', type=Path, required=True)
    parser.add_argument('--out', type=Path, default=Path('isme_tepki/models/directmhp_cmu_s.torchscript.pt'))
    args = parser.parse_args()
    try:
        export(args.source.resolve(), args.weights.resolve(), args.out.resolve())
    except (OSError, ImportError, ValueError) as exc:
        parser.exit(1, f'{exc}\n')
    print(args.out.resolve())


if __name__ == '__main__':
    main()

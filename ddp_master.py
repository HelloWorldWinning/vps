import torch
import torch.distributed as dist
import os

def init_process(rank=0, size=2, backend='gloo'):
    os.environ['MASTER_ADDR'] = os.getenv('MASTER_ADDR', '34.84.75.37')
    os.environ['MASTER_PORT'] = os.getenv('MASTER_PORT', '29500')
    dist.init_process_group(backend, rank=rank, world_size=size)

def main():
    rank = int(os.getenv('RANK', '0'))
    size = int(os.getenv('SIZE', '2'))
    init_process(rank, size)

    tensor = torch.zeros(1)
    dist.all_reduce(tensor, op=dist.ReduceOp.SUM)

    if rank == 0:
        print('Master, Rank:', rank, 'has tensor:', tensor)
    else:
        print('Client, Rank:', rank, 'has tensor:', tensor)

if __name__ == "__main__":
    main()


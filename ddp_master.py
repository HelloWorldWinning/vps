import torch
import torch.distributed as dist
import os

def init_process(rank, size, backend='gloo'):
   #os.environ['MASTER_ADDR'] = 'a1.wjwy.today'  # Change to your master's IP address when running on different machines
    os.environ['MASTER_ADDR'] = '34.84.75.37'
    os.environ['MASTER_PORT'] = '29500'
    dist.init_process_group(backend, rank=rank, world_size=size)

def main():
    rank = 0
    size = 2  # Total number of processes in the distributed environment
    init_process(rank, size)

    # Example of a distributed operation
    tensor = torch.zeros(1)
    dist.all_reduce(tensor, op=dist.ReduceOp.SUM)

    if rank == 0:
        print('Master, Rank:', rank, 'has tensor:', tensor)
    else:
        print('Client, Rank:', rank, 'has tensor:', tensor)


if __name__ == "__main__":
    main()

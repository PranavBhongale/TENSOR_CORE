import numpy as np

TILE = 8

def gelu(x):
    return 0.5*x*(1+np.tanh(np.sqrt(2/np.pi)*(x+0.044715*x**3)))

def tile_golden(A, B, C):

    M, K = A.shape
    K, N = B.shape

    Y = np.zeros((M,N))

    for ti in range(0, M, TILE):
        for tj in range(0, N, TILE):

            acc = np.zeros((TILE,TILE))

            for tk in range(0, K, TILE):

                A_tile = A[ti:ti+TILE, tk:tk+TILE]
                B_tile = B[tk:tk+TILE, tj:tj+TILE]

                acc += np.matmul(A_tile, B_tile)

            acc += C[ti:ti+TILE, tj:tj+TILE]

            Y[ti:ti+TILE, tj:tj+TILE] = gelu(acc)

    return Y

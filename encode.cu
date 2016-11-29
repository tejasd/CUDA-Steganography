#include <fstream>
#include <iostream>
#include <iomanip>
#include <cuda.h>
#include <cuda_runtime.h>
#include <cuda_runtime_api.h>
#include <math.h>

using namespace std;

//Execute 1 thread per pixel of output image.
//Requires no atomics
__global__ void encode_per_pixel_kernel(uchar4* const d_destImg,
                              const char* const d_binData,
                              int numBytesData)
{
  int pixel = threadIdx.x + blockDim.x * blockIdx.x;
  if(pixel >= numBytesData)
    return;
  
  //Pixel 5 is at byte 3.
  int dataStart = pixel / 2 + 1;
  int nibble = pixel % 2;

  char dataByte = d_binData[dataStart];
  
  //Can't do next part in a loop because we have to access differently (x,y,z,w)
  
  //Channel 0 (first bit in the nibble)
  int offset = (7 - 1 * nibble);
  char mask = 1 << offset;
  char bit = (dataByte & mask) >> offset;
  d_destImg[pixel].x += bit;
  
  //Channel 1 (2nd bit)
  offset -= 1;
  mask >>= 1;
  bit = (dataByte & mask) >> offset;
  d_destImg[pixel].y += bit;
  
  //Channel 2 (3rd bit)
  offset -= 1;
  mask >>= 1;
  bit = (dataByte & mask) >> offset;
  d_destImg[pixel].z += bit;
  
  //Channel 3 (4th bit)
  offset -= 1;
  mask >>= 1;
  bit = (dataByte & mask) >> offset;
  d_destImg[pixel].z += bit;
  
}

/**

| 10 11 12 15 ; 11 255 12 0 |
| 15 10 13 5  ; 15 14 19 80 | Original image (each set of 4 is 1 pixel).
| 12 14 16 21 ; 14 18 10 16 |
| 10 10 10 10 ; 10 10 10 10 |

+

[ 1001 0110 1111 0000 1010 0101 0100 1100]  Data file

= 

| 11 11 12 16 ; 11 0  13 0  |
| 15 11 14 6  ; 15 14 19 80 | Encoded image
| 13 14 16 21 ; 14 19 10 17 |
| 10 11 10 10 ; 11 11 10 10 |
 
 */
void encode_parallel(const uchar4* const h_sourceImg,
                     uchar4* const h_destImg,
                     const char* const h_binData,
                     int numBytesData,
                     const size_t numRowsSource, const size_t numColsSource)
{

  //Allocate device memory
  uchar4* d_destImg;
  char* d_binData;
  cudaMalloc(&d_destImg, sizeof(uchar4) * numRowsSource * numColsSource);
  cudaMalloc(&d_binData, sizeof(char) * numBytesData);
  
  cudaMemcpy(d_destImg, h_sourceImg, sizeof(uchar4) * numRowsSource * numColsSource, cudaMemcpyHostToDevice); 
  cudaMemcpy(d_binData, h_binData, numBytesData, cudaMemcpyHostToDevice);

  //Execute 1 thread per pixel of output image.
  //This means 1 thread per 4 bits of data.
  int numThreads = ceil(numBytesData / 4.0);
  int blockSize = 1024;
  int numBlocks = ceil((float)numThreads / blockSize);
  
  cout << "numBlocks: " << numBlocks << " blockSize: " << blockSize << " numThreads: " << numThreads << endl;
  
  encode_per_pixel_kernel<<<numBlocks, numThreads>>>(d_destImg, d_binData, numBytesData);
  
  cudaMemcpy(h_destImg, d_destImg, sizeof(uchar4) * numRowsSource * numColsSource, cudaMemcpyDeviceToHost);
  
  //Free memory
  cudaFree(d_destImg);
  cudaFree(d_binData);
                  
}

echo "Choose PyTorch installation option:"
echo "1. CPU only (default)"
echo "2. CUDA 12.1"
echo "3. CUDA 11.8"
read -t 5 -p "Enter your choice_pytorch [1-3] (default: 1): " choice_pytorch





git clone https://github.com/freqtrade/freqtrade.git

git clone https://github.com/freqtrade/freqtrade-strategies.git

# Install necessary tools
sudo apt-get update -y
sudo apt-get install -y build-essential 
# Download TA-Lib
# wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz
wget --inet4-only -O  ta-lib-0.4.0-src.tar.gz  http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz

# Extract and install TA-Lib
tar -xzf ta-lib-0.4.0-src.tar.gz
cd ta-lib/
./configure --prefix=/usr
make
sudo make install

pip install TA-Lib
pip install freqtrade
pip install datasieve
pip install    plotly   scipy matplotlib
pip install -U scikit-learn


pip3 install -U scikit-learn
pip3 install datasieve

cd ..
rm -r  ta-lib-0.4.0-src.tar.gz



case $choice_pytorch in
  2)
    echo "Installing PyTorch with CUDA 12.1"
    conda install pytorch torchvision torchaudio pytorch-cuda=12.1 -c pytorch -c nvidia
    ;;
  3)
    echo "Installing PyTorch with CUDA 11.8"
    conda install pytorch torchvision torchaudio pytorch-cuda=11.8 -c pytorch -c nvidia
    ;;
  *)
    echo "Installing PyTorch with CPU only"
    conda install pytorch torchvision torchaudio cpuonly -c pytorch
    ;;
esac

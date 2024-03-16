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





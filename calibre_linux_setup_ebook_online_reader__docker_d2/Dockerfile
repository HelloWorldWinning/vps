FROM python:3.9-slim

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
#ENV CALIBRE_LIBRARY_PATH=/data/calibre-library
ENV CALIBRE_LIBRARY_PATH=/calibre-library
ENV EBOOK_DOWNLOAD_PATH=/books

# Install necessary dependencies
#   git \
RUN apt-get update && apt-get install -y \
    wget \
    xz-utils \
    libegl1 \
    libopengl0 \
    libxcb-cursor0 \
    libxkbcommon0 \
    libgl1-mesa-glx \
    libfreetype6 \
    libfontconfig1 \
    libxrender1 \
    libxext6 \
    libx11-6 \
    libnss3 \
    libxcomposite1 \
    libxrandr2 \
    libxtst6 \
    libxdamage1 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libasound2 \
    libatk1.0-0 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libexpat1 \
    libgcc1 \
    libgconf-2-4 \
    libgdk-pixbuf2.0-0 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libpci3 \
    libpcre3 \
    libpixman-1-0 \
    libstdc++6 \
    libdrm2 \
    libgbm1 \
    xdg-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Calibre
RUN wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | sh /dev/stdin

# Set up directories
RUN mkdir -p $EBOOK_DOWNLOAD_PATH $CALIBRE_LIBRARY_PATH

## Clone the books repository
#RUN git clone --depth 1 --filter=blob:none --sparse https://github.com/HelloWorldWinning/books.git /tmp/books \
#    && cd /tmp/books \
#    && git sparse-checkout set default_d \
#    && git pull origin main \
#    && mv default_d/* $EBOOK_DOWNLOAD_PATH \
#    && cd / \
#    && rm -rf /tmp/books
#
# Add books to Calibre library
#RUN calibredb add -r $EBOOK_DOWNLOAD_PATH/* --library-path $CALIBRE_LIBRARY_PATH

# Set up Calibre user
RUN calibre-server --manage-users -- add a a

# Remove downloaded books to save space
#RUN rm -rf $EBOOK_DOWNLOAD_PATH/*

# Expose the Calibre server port
EXPOSE 8080

# Start Calibre server
#CMD ["calibre-server", "--port=8080", "--enable-auth", "--disable-use-bonjour", "/data/calibre-library"]

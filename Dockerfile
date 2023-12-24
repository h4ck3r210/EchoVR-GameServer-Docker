FROM alpine

# Wine for running the GameServer
RUN apk add --no-cache wine wget jq bash curl

# Set 
ENV WINEDEBUG=-all

# Configure Wine
RUN rm -rf /root/.wine

# Set the workdir
WORKDIR /root

# Copy the monitor script
COPY monitor.sh .

COPY Ssettings.json .

ENTRYPOINT ["/bin/bash", "/root/monitor.sh"]
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y sudo 

# Create test user with passwordless sudo
RUN useradd -m -s /bin/bash testuser \
 && echo "testuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/testuser \
 && chmod 0440 /etc/sudoers.d/testuser

USER testuser
WORKDIR /home/testuser

COPY --chown=testuser:testuser setup.sh /home/testuser/setup.sh

RUN chmod +x /home/testuser/setup.sh

CMD ["/bin/bash"]
FROM centos:centos7

# Install any required system packages. We need the Apache httpd web
# server in this instance, plus the 'rsync' package so we can copy
# files into the running container if necessary.

RUN rpmkeys --import file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7 && \
    PACKAGES="httpd rsync" && \
    yum install -y --setopt=tsflags=nodocs ${PACKAGES} && \
    rpm -V ${PACKAGES} && \
    yum clean all -y

# Create a non root account called 'default' to be the owner of all the
# files which the Apache httpd server will be hosting. This account
# needs to be in group 'root' (gid=0) as that is the group that the
# Apache httpd server would use if the container is later run with a
# unique user ID not present in the host account database, using the
# command 'docker run -u'.

ENV HOME=/opt/app-root

RUN mkdir -p ${HOME} && \
    useradd -u 1001 -r -g 0 -d ${HOME} -s /sbin/nologin \
            -c "Default Application User" default

# Modify the default Apache configuration to listen on a non privileged
# port of 8080, log everything to stdout/stderr, use different runtime
# directory and host files from under the account created to hold files.

RUN mkdir -p ${HOME}/htdocs && \
    sed -ri -e 's/^Listen 80$/Listen 8080/' \
            -e 's%logs/access_log%/proc/self/fd/1%' \
            -e 's%logs/error_log%/proc/self/fd/2%' \
            -e 's%/var/www/html%${HOME}/htdocs%' \
            /etc/httpd/conf/httpd.conf && \
    echo "DefaultRuntimeDir ${HOME}" >> /etc/httpd/conf/httpd.conf && \
    echo "PidFile ${HOME}/httpd.pid" >> /etc/httpd/conf/httpd.conf

EXPOSE 8080

# Copy into place S2I builder scripts and label the Docker image so that
# the 's2i' program knows where to find them.

COPY s2i $HOME/s2i

LABEL io.k8s.description="S2I builder for hosting files with Apache HTTPD server" \
      io.k8s.display-name="Apache HTTPD Server" \
      io.openshift.expose-services="8080:http" \
      io.openshift.tags="builder,httpd" \
      io.openshift.s2i.scripts-url="image://${HOME}/s2i/bin"

# Fixup all the directories under the account so they are group writable
# to the 'root' group (gid=0) so they can be updated if necessary, such
# as would occur if using 'oc rsync' to copy files into a container.

RUN chown -R 1001:0 /opt/app-root && \
    find ${HOME} -type d -exec chmod g+ws {} \;

# Ensure container runs as non root account from its home directory.

WORKDIR ${HOME}

USER 1001

# Set the Apache httpd server to be run when the container is run. Must
# be run in the foreground else Apache httpd server will daemonise itself.

CMD [ "httpd", "-DFOREGROUND" ]
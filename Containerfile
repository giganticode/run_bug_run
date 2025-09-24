
FROM ubuntu:24.04

# Set a non-interactive frontend for apt-get to avoid prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies for rbenv and Ruby compilation
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    build-essential \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    autoconf \
    bison \
    libyaml-dev \
    libffi-dev \
    libgdbm-dev \
    libncurses5-dev \
    libtool \
    pkg-config \
    libsqlite3-0 \
    sqlite3 \
    bubblewrap \
    php-cli \
    python3 \
    python3-numpy \
    ruby \
    mono-mcs \
    mono-runtime \
    golang \
    g++ \
    gcc \
    lrzip \
    nodejs \
    openjdk-17-jdk \
    openjdk-17-jre \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user
ARG USERNAME=rbr
ARG USER_UID=1001
ARG USER_GID=1001
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    # Add sudo support for the user
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Switch to the non-root user
USER $USERNAME
WORKDIR /home/$USERNAME

# Install rbenv
ENV RBENV_ROOT="/home/$USERNAME/.rbenv"
ENV PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:$PATH"
RUN git clone https://github.com/rbenv/rbenv.git $RBENV_ROOT

# Add rbenv to shell configuration (for bash)
RUN echo 'eval "$(rbenv init -)"' >> /home/$USERNAME/.bashrc

# Install ruby-build (rbenv plugin)
ENV RUBY_BUILD_DIR="$RBENV_ROOT/plugins/ruby-build"
RUN mkdir -p $RUBY_BUILD_DIR \
    && git clone https://github.com/rbenv/ruby-build.git $RUBY_BUILD_DIR

# Install a specific Ruby version (e.g., 3.2.2)
# You can change this to your desired Ruby version
ENV RUBY_VERSION 3.4.2
RUN rbenv install $RUBY_VERSION \
    && rbenv global $RUBY_VERSION

# Install Bundler
RUN echo "gem: --no-document" > /home/$USERNAME/.gemrc \
    && gem install bundler

# Verify Ruby installation
RUN ruby -v
RUN gem -v
RUN bundle -v
RUN gem install rake

# For cache
ADD "https://api.github.com/repos/furunkel/tree_sitter/commits" tree_sitter_commits.json
RUN rm tree_sitter_commits.json

RUN git clone https://github.com/furunkel/tree_sitter.git "/home/$USERNAME/deps/tree_sitter"

# For cache
ADD "https://api.github.com/repos/furunkel/tree_sitter-diff/commits" tree_sitter_diff_commits.json
RUN rm tree_sitter_diff_commits.json

RUN git clone https://github.com/furunkel/tree_sitter-diff.git "/home/$USERNAME/deps/tree_sitter-diff"

RUN bundle config set local.tree_sitter-diff "/home/$USERNAME/deps/tree_sitter-diff"
RUN bundle config set local.tree_sitter "/home/$USERNAME/deps/tree_sitter"

WORKDIR "/home/$USERNAME/deps/tree_sitter"
RUN bundle install
RUN rake compile

WORKDIR "/home/$USERNAME/deps/tree_sitter-diff"
RUN bundle install
RUN rake compile


RUN mkdir -p "/home/$USERNAME/bundle/bundle" \
    && mkdir -p "/home/$USERNAME/bundle/cache" \
    && mkdir -p "/home/$USERNAME/bundle/config"

ENV BUNDLE_PATH="/home/$USERNAME/bundle/bundle"
ENV BUNDLE_WITHOUT="experiments"
ENV BUNDLE_CACHE_PATH="/home/$USERNAME/bundle/cache"
ENV BUNDLE_APP_CONFIG="/home/$USERNAME/bundle/config"

COPY --chown=$USERNAME:$USERNAME . "/home/$USERNAME/rbr"
WORKDIR /home/$USERNAME/rbr

#RUN lrunzip -z db/dump.sql.lrz -o db/dump.sql
#RUN sqlite3 db/development.db < db/dump.sql && rm db/dump.sql

RUN chown -R $USERNAME:$USERNAME "/home/$USERNAME/rbr"
RUN bundle

# Default command (optional)
CMD ["bash"]

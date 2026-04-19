#!/bin/sh

# OS detection
unameOut="$(uname -s)"
case "${unameOut}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Mac;;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGw;;
    *)          machine="UNKNOWN:${unameOut}"
esac

# If we're on macOS...
echo "==> Mac specific stuff"
if [ "$machine" == "Mac" ]; then
    echo "We're on a Mac... checking homebrew and neofetch..."
    ## Install homebrew
    if ! [[ -x "$(command -v brew)" ]]; then
        echo "homebrew not installed yet; installing"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    else
        echo "homebrew already installed; skipping"
    fi
    echo "fixing homebrew permissions so compinit doesn't complain..."
    chmod go-w "$(brew --prefix)/share"
    echo
    ## Install fastfetch
    ### THIS SHOULD BE MOVED OUT INTO IT'S OWN BLOCK WITH PACKAGE MANAGER DETECTION, RATHER THAN OS DETECTION
    if ! [[ -x "$(command -v fastfetch)" ]]; then
        echo "fastfetch not installed yet; installing"
        brew install fastfetch
    else
        echo "fastfetch already installed; skipping"
    fi
fi
echo

# directory setup portion
echo "==> Directory setup"
if ! [ -d $HOME/.config/neofetch ]; then
    echo "config dir doesn't exist; making"
	mkdir -p $HOME/.config/neofetch
else
    echo "config dir already exists; skipping"
fi
echo

# zsh portion
echo "==> zsh"

# Install oh my zsh
if ! [ -d $HOME/.oh-my-zsh ]; then
    echo "oh my zsh not yet installed; installing"
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "oh my zsh already installed; skipping"
fi
echo

# Link zshrc
if [ -w $HOME/.zshrc ]; then
    echo "zsh config already exists; backing up..."
    mv -f $HOME/.zshrc $HOME/.zshrc.old
fi
echo "Linking zsh config"
ln -s $HOME/dotfiles/zsh/.zshrc $HOME/.zshrc
echo

# Install p10k
if ! [ -d $HOME/.oh-my-zsh/custom/themes/powerlevel10k ]; then
    echo "p10k not installed; installing"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/powerlevel10k
else
    echo "p10k already installed; skipping"
fi

# Link p10k config
if [ -w $HOME/.p10k.zsh ]; then
    echo "p10k config already exists; backing up..."
    mv -f $HOME/.p10k.zsh $HOME/.p10k.zsh.old
fi
echo "Linking p10k config"
ln -s $HOME/dotfiles/zsh/.p10k.zsh $HOME/.p10k.zsh
echo

# Install zsh plugins
echo "Installing zsh plugins"

## zsh-syntax-highlighting
if ! [ -d ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting ]; then
    echo "zsh-syntax-highlighting; installing"
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
else
    echo "zsh-syntax-highlighting already installed; skipping"
fi


## Install zsh-completions
if ! [ -d ${ZSH_CUSTOM:=~/.oh-my-zsh/custom}/plugins/zsh-completions ]; then
    echo "zsh-completions; installing"
    git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:=~/.oh-my-zsh/custom}/plugins/zsh-completions
else
    echo "zsh-completions already installed; skipping"
fi
echo

# git config
echo "==> git config"
if [[ -x "$(command -v git)" ]]; then
    echo "git is installed. checking for vim."
    if [[ -x "$(command -v vim)" ]]; then
        echo "vim is installed. setting git editor to vim."
        git config --global core.editor "vim"
    else
        echo "vim is not installed. skipping."
    fi
else
    echo "git is not installed. skipping."
fi
echo

# lscolors
echo "==> lscolors"
if [ -w $HOME/.dir_colors ]; then
    echo "dir_colors config already exists; backing up..."
    mv -f $HOME/.dir_colors $HOME/.dir_colors.old
fi
echo "Linking dir_colors config"
    ln -s $HOME/dotfiles/dir_colors/.dir_colors $HOME/.dir_colors
echo

# vim config
echo "==> vim"
if [ -w $HOME/.vimrc ]; then
    echo "vim config already exists; backing up..."
    mv -f $HOME/.vimrc $HOME/.vimrc.old
fi
echo "Linking vim config"
    ln -s $HOME/dotfiles/vim/.vimrc $HOME/.vimrc
echo

# Link neofetch config, if installed, and install if not
echo "==> fastfetch"
if [[ -x "$(command -v fastfetch)" ]]; then
    if [ -w $HOME/.config/neofetch/config.conf ]; then
        echo "neofetch config already exists; backing up..."
        mv -f $HOME/.config/neofetch/config.conf $HOME/.config/neofetch/config.conf.old
    fi
    echo "Linking fastfetch config"
    ln -s $HOME/dotfiles/fastfetch/config.conf $HOME/.config/fastfetch/config.conf
    echo "Running fastfetch..."
    echo
    fastfetch
fi

# Install tmux
echo "==> tmux"
if ! [[ -x "$(command -v tmux)" ]]; then
	echo "tmux not installed yet; installing"
	brew install tmux
else
	echo "tmux already installed; skipping"
fi
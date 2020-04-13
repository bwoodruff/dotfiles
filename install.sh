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
    echo "We're on a Mac... checking homebrew..."
    ## Install homebrew
    if ! [[ -x "$(command -v brew)" ]]; then
        echo "homebrew not installed yet; installing"
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    else
        echo "homebrew already installed; skipping"
    fi
    echo
    ## Install neofetch
    if ! [[ -x "$(command -v neofetch)" ]]; then
        echo "neofetch not installed yet; installing"
        brew install neofetch
    else
        echo "neofetch already installed; skipping"
    fi
fi
echo

echo "==> Directory setup"

# Check for config dir and make it if it doesn't exist
if ! [ -d $HOME/.config ]; then
    echo "config dir doesn't exist; making"
	mkdir $HOME/.config
fi

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
echo

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

# Link neofetch config, if installed
if [[ -x "$(command -v neofetch)" ]]; then
    if [ -w $HOME/.config/neofetch/config.conf ]; then
        echo "neofetch config already exists; backing up..."
        mv -f $HOME/.config/neofetch/config.conf $HOME/.config/neofetch/config.conf.old
    fi
    echo "Linking neofetch config"
    ln -s $HOME/dotfiles/neofetch/config.conf $HOME/.config/neofetch/config.conf
    
    echo "Running neofetch..."
    echo
    neofetch
fi
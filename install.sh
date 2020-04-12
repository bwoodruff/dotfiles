#!/bin/sh

# Install oh my zsh

if ! [ -d $HOME/.oh-my-zsh ]; then
    echo "oh my zsh not yet installed; installing"
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "oh my zsh already installed; skipping"
fi

# Link zshrc

if [ -w $HOME/.zshrc ]; then
    echo "zshrc already exists; backing up..."
    mv -f $HOME/.zshrc $HOME/.zshrc.old
fi

echo "Linking zsh config"
ln -s $HOME/dotfiles/zsh/.zshrc $HOME/.zshrc

# Install p10k

if ! [ -d $HOME/.oh-my-zsh/custom/themes/powerlevel10k ]; then
    echo "p10k not installed; installing"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/powerlevel10k
else
    echo "p10k already installed; skipping"
fi

# Link p10k config

if [ -w $HOME/.p10k.zsh ]; then
    echo "p10k already exists; backing up..."
    mv -f $HOME/.p10k.zsh $HOME/.p10k.zsh.old
fi

echo "Linking p10k config"
ln -s $HOME/dotfiles/zsh/.p10k.zsh $HOME/.p10k.zsh

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
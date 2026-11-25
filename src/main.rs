use clap::{Parser, Subcommand};

use std::ffi::OsString;
use std::fs;

#[derive(Parser)]
#[command(version, about, long_about = None)]
#[command(propagate_version = true)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Send { file_dir: OsString },
    Receive { file_dir: OsString },
}

fn main() {
    let cli = Cli::parse();

    match &cli.command {
        Commands::Send { file_dir } => {
            send(fs::read(file_dir).unwrap());
        }
        Commands::Receive { file_dir } => {
            println!("{file_dir:?}");
        }
    }
}

fn send(content: Vec<u8>) {
    let mut count: [u32; 256] = [0; 256];

    for i in content {
        count[i as usize] += 1;
    }

    for i in count {
        print!("{i}, ");
    }
}



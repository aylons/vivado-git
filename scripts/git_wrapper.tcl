################################################################################
#
# This file provides a basic wrapper to use git directly from the tcl console in
# Vivado.
# It requires the write_project_tcl_git.tcl script to work properly.
# Unversioned files will be put in the vivado_project folder
#
# Ricardo Barbedo
#
################################################################################

namespace eval ::git_wrapper {
    namespace export git
    namespace export wproj
    namespace export update_bd
    namespace import ::custom_projutils::write_project_tcl_git
    namespace import ::current_project
    namespace import ::common::get_property

    proc git {args} {
        set command [lindex $args 0]

        # Change directory project directory if not in it yet
        set proj_dir [regsub {\/vivado_project$} [get_property DIRECTORY [current_project]] {}]
        set current_dir [pwd]
        if {
            [string compare -nocase $proj_dir $current_dir]
        } then {
            puts "Not in project directory"
            puts "Changing directory to: ${proj_dir}"
            cd $proj_dir
        }

        switch $command {
            "init" {git_init {*}$args}
            "commit" {git_commit {*}$args}
            "default" {exec git {*}$args}
        }
    }

    proc git_init {args} {
        # Generate gitignore file
        set file [open ".gitignore" "w"]
        puts $file "vivado_project/*"
        close $file

        # Initialize the repo
        exec git {*}$args
        exec git add .gitignore
    }

    proc git_commit {args} {
        # Refuse to commit if the "-m" flag is not present, to avoid
        # getting stuck in the Tcl console if a terminal editor is used
        if { !("-m"  in $args) } {
            send_msg_id Vivado-git-001 ERROR "Please use the -m option to include a message when committing.\n"
            return
        }

        # Get project name
        set proj_file [current_project].tcl

        # Generate project and add it
        write_project_tcl_git -no_copy_sources -force $proj_file
        puts $proj_file
        exec git add $proj_file

        # Now commit everything
        exec git {*}$args
    }

    proc update_bd {{bd_name ""}} {
        # Change directory to project directory if not in it yet
        set proj_dir [regsub {\/vivado_project$} [get_property DIRECTORY [current_project]] {}]
        set current_dir [pwd]
        if {
            [string compare -nocase $proj_dir $current_dir]
        } then {
            puts "Not in project directory"
            puts "Changing directory to: ${proj_dir}"
            cd $proj_dir
        }

        set origin_dir $proj_dir

        if { $bd_name == "" } {
            set bd_tcl_files [glob -nocomplain -directory [file join $origin_dir "src/bd"] *.tcl]
            if { [llength $bd_tcl_files] == 0 } {
                puts "No BD tcl files found in src/bd/"
                return
            }
        } else {
            set bd_tcl_files [list [file join $origin_dir "src/bd" "${bd_name}.tcl"]]
        }

        foreach bd_tcl_file $bd_tcl_files {
            set bd_base [file rootname [file tail $bd_tcl_file]]

            if { ![file exists $bd_tcl_file] } {
                puts "ERROR: BD tcl file not found: $bd_tcl_file"
                continue
            }

            # Check if the BD tcl source is newer than the existing .bd file
            set proj_name [get_property name [current_project]]
            set bd_dir [file join [get_property directory [current_project]] "${proj_name}.srcs" "sources_1" "bd" $bd_base]
            set bd_file_on_disk [file join $bd_dir "${bd_base}.bd"]

            if { [file exists $bd_file_on_disk] } {
                set tcl_mtime [file mtime $bd_tcl_file]
                set bd_mtime [file mtime $bd_file_on_disk]
                if { $tcl_mtime <= $bd_mtime } {
                    puts "BD $bd_base is up to date, skipping."
                    continue
                }
            }

            puts "BD $bd_base needs updating..."

            # Close the BD if it's open
            catch { close_bd_design [get_bd_designs -quiet $bd_base] }

            # Remove existing BD from project if it exists, but keep output products
            set existing_bd [get_files -quiet ${bd_base}.bd]
            if { $existing_bd != "" } {
                remove_files $existing_bd
                puts "Removed existing BD reference: $bd_base"
            }

            # Delete only the old .bd file on disk so the proc can recreate it
            if { [file exists $bd_file_on_disk] } {
                file delete $bd_file_on_disk
            }

            # Source the BD tcl file (defines the cr_bd_* proc)
            source $bd_tcl_file

            # Call the proc to recreate the BD
            set proc_name "cr_bd_${bd_base}"
            if { [info procs $proc_name] != "" } {
                puts "Calling $proc_name to recreate BD..."
                $proc_name ""
                puts "BD $bd_base recreated successfully."

                # Regenerate wrapper
                make_wrapper -files [get_files ${bd_base}.bd] -top -import
                puts "Wrapper regenerated for $bd_base"
            } else {
                puts "ERROR: Proc $proc_name not found in $bd_tcl_file"
            }
        }
    }

    proc wproj {} {
        # Change directory project directory if not in it yet
        set proj_dir [regsub {\/vivado_project$} [get_property DIRECTORY [current_project]] {}]
        set current_dir [pwd]
        if {
            [string compare -nocase $proj_dir $current_dir]
        } then {
            puts "Not in project directory"
            puts "Changing directory to: ${proj_dir}"
            cd $proj_dir
        }

        # Generate project
        set proj_file [current_project].tcl
        puts $proj_file
        write_project_tcl_git -no_copy_sources -force $proj_file
    }
}

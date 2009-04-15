#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

terse=
driver=default_driver
label_tpl="%n"

## Parse options

while [ -n "$1" ]; do
    arg="$1"; shift
    case "$arg" in
	-t)
	    terse=1
            driver=cat
            ;;
	"--graph="*)
	    graph=1
            driver=${arg#--graph=}_driver
            ;;
	"--label="*)
            label_tpl=${arg#--label=}
            ;;
	*)
	    echo "Usage: tg [...] summary [-t | --graph=<driver>]" >&2
	    echo '  where <driver> is one of "dot", "txt"' >&2
	    exit 1;;
    esac
done

curname="$(git symbolic-ref HEAD | sed 's#^refs/\(heads\|top-bases\)/##')"

! [ -n "$terse" -a -n "$graph" ] ||
	die "-t and --graph options are mutual exclusive"

# $current$nonempty$remote$rem_update$deps_update$deps_missing$base_update 
# $rev 
# $name"
get_label() {
    flags=$1
    r=$2
    n=$3
    N=${n#t/}

    echo $flags | sed 's/\(.\)/\1 /g' | {
        read c e R U u d b
        
        label='"'$label_tpl'"'
        new_label=""
        
        while [ true ]; do
            new_label=`echo $label | sed 's/%\(\.[0-9]\)\?\([^.s]\)\(.*\)/%\1s\3 \$\2/'`
            if [ "$new_label" = "$label" ]; then
                break
            fi
            label=$new_label
        done

        echo `eval "printf $new_label"`
    }
}

default_driver() {
    while read flags rev name label; do
        flags=`echo $flags | tr '.' ' '`
	if [ "$(git rev-parse "$name")" != "$rev" ]; then
	    subject="$(git cat-file blob "$name:.topmsg" | sed -n 's/^Subject: //p')"
	else
            # No commits yet
	    subject="(No commits)"
	fi

	printf '%s\t%-31s\t%s\n' "$flags" "$name" "$subject"
    done
}

dot_driver() {
    cat <<EOT
# GraphViz output; pipe to:
#   | dot -Tpng -o <ouput>
# or
#   | dot -Txlib

digraph G {

graph [
  rankdir = "TB"
  label="TopGit Layout\n\n\n"
  fontsize = 14
  labelloc=top
  pad = "0.5,0.5"
];

EOT

    while read flags rev name label; do
        echo "{node [label=\"$label\"] \"$name\";}"
	git cat-file blob "$name:.topdeps" | while read dep; do
	    dep_is_tgish=true
	    ref_exists "refs/top-bases/$dep"  ||
	    dep_is_tgish=false
	    if ! "$dep_is_tgish" || ! branch_annihilated $dep; then
		echo "\"$name\" -> \"$dep\";"
	    fi
	done
    done | sort # hack: make sure lines starting with a brace come first

    echo '}'
}

txt_driver() {
    which graph-easy >/dev/null || die '"graph-easy" not found. See http://search.cpan.org/dist/Graph-Easy/'
    dot_driver | graph-easy --as=ascii --from=dot 2>/dev/null
}

git for-each-ref refs/top-bases |
	while read rev type ref; do
		name="${ref#refs/top-bases/}"
		if branch_annihilated "$name"; then
			continue;
		fi;

		if [ -n "$terse" ]; then
			echo "$name"
			continue
		fi

		missing_deps=

		current='.'
		[ "$name" != "$curname" ] || current='>'
		nonempty='.'
		! branch_empty "$name" || nonempty='0'
		remote='.'
		[ -z "$base_remote" ] || remote='l'
		! has_remote "$name" || remote='r'
		rem_update='.'
		[ "$remote" != 'r' ] || ! ref_exists "refs/remotes/$base_remote/top-bases/$name" || {
			branch_contains "refs/top-bases/$name" "refs/remotes/$base_remote/top-bases/$name" &&
			branch_contains "$name" "refs/remotes/$base_remote/$name"
		} || rem_update='R'
		[ "$rem_update" = 'R' ] || branch_contains "refs/remotes/$base_remote/$name" "$name" 2>/dev/null ||
			rem_update='L'
		deps_update='.'
		needs_update "$name" >/dev/null || deps_update='D'
		deps_missing='.'
		[ -z "$missing_deps" ] || deps_missing='!'
		base_update='.'
		branch_contains "$name" "refs/top-bases/$name" || base_update='B'

                flags="$current$nonempty$remote$rem_update$deps_update$deps_missing$base_update"
                label=`get_label "$flags" "$rev" "$name"`
		printf '%s %s %s %s\n' "$flags" "$rev" "$name" "$label"
	done | $driver

# vim:noet

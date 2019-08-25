#!/bin/bash

echo2()   { echo   "$@" >&2 ; }
printf2() { printf "$@" >&2 ; }

DIE()   { echo2 "Error: $1." ; exit 1 ; }
WARN()  { echo2 "Warning: $1." ; }

TODO()  { DIE "${FUNCNAME[1]}: todo" ; }

Pushd() { pushd "$@" >/dev/null || DIE "${FUNCNAME[1]}: pushd $* failed" ; }

Popd()  {
    local count=1 xx
    case "$1" in
        -c=*) count=${1:3} ; shift ;;
        -c*)  count=${1:2} ; shift ;;
    esac
    for ((xx=0;xx<count;xx++)) ; do
        popd  "$@" >/dev/null || DIE "${FUNCNAME[1]}: popd $* failed"
    done
}

Build()
{
    local pkgdirname="$1"
    local assetsdir="$2"
    local pkgbuilddir="$3"
    local pkgname
    local pkg
    local workdir=$(mktemp -d)

    Pushd "$workdir"
      cp -r "$pkgbuilddir" .
      pkgname="$(PkgBuildName "$pkgdirname")"
      Pushd "$pkgdirname"
        # now build, assume we have PKGBUILD
        makepkg -sc >/dev/null || { Popd -c2 ; DIE "makepkg for '$pkgname' failed" ; }
        pkg="$(ls -1 ${pkgname}-*.pkg.tar.xz)"
        mv $pkg "$assetsdir"
        pkg="$assetsdir/$pkg"
      Popd
    Popd
    rm -rf "$workdir"
    echo "$pkg"
}

PkgBuildName()
{
    local pkgdirname="$1"
    source "$PKGBUILD_ROOTDIR"/"$(basename "$pkgdirname")"/PKGBUILD
    echo "$pkgname"
}

PkgBuildVersion()
{
    local pkgdirname="$1"
    source "$PKGBUILD_ROOTDIR"/"$(basename "$pkgdirname")"/PKGBUILD
    echo "${pkgver}-$pkgrel"
}

LocalVersion()
{
    local Pkgname="$1"
    Pkgname="$(basename "$Pkgname")"
    #local pkgdirname="$1"
    #local Pkgname="$(PkgBuildName "$pkgdirname")"

    local tail="$(ls -1 "$ASSETSDIR"/${Pkgname}-*.pkg.tar.xz 2>/dev/null | sed 's|^.*/'"$Pkgname"'-||')"
    local ver="$(echo "$tail" | cut -d '-' -f 1)"
    local rel="$(echo "$tail" | cut -d '-' -f 2)"

    echo "${ver}-$rel"
}

ListNameToPkgName()
{
    # PKGNAMES array (from $ASSETS_CONF) uses certain syntax for package names
    # to mark where they come from, either local or AUR packages.
    # AUR packages are fetched from AUR, local packages
    # are simply used from a local folder.
    #
    # Supported syntax:
    #    pkgname          local package
    #    ./pkgname        local package (emphasis)
    #    aur/pkgname      AUR package

    local xx="$1"
    local fetch="$2"
    local pkgname

    if [ "${xx::2}" = "./" ] ; then
        pkgname="${xx:2}"
    elif [ "${xx::4}" = "aur/" ] ; then
        pkgname="${xx:4}"
        case "$fetch" in
            yes) yay -Ga "$pkgname" >/dev/null || return 1 ;;
        esac
    else
        pkgname="${xx}"
    fi
    echo "$pkgname"
}

Assets_clone()
{
    local xx

    # echo2 "It is possible that your local release assets in folder $ASSETSDIR"
    # echo2 "are not in sync with github."
    # echo2 "If so, you can delete your local assets and fetch assets from github now."
    # read -p "Delete local assets and fetch them from github now (y/N)? " xx >&2

    printf2 "\n%s " "Fetch assets from github (y/N)?"
    read xx

    case "$xx" in
        [yY]*) ;;
        *)
            echo2 "Using local assets."
            echo2 ""
            return
            ;;
    esac

    Pushd "$ASSETSDIR"

    echo "Deleting all local assets..."
    # $pkgname in PKGBUILD may not be the same as values in $PKGNAMES,
    # so delete all possible packages.
    rm -f *.pkg.tar.xz{,.sig}
    rm -f "$REPONAME".{db,files}{,.tar.xz,.tar.xz.old}

    echo "Fetching all github assets..."
    for xx in "${RELEASE_TAGS[@]}" ; do
        hub release download $xx
        break
        # we need assets from only one tag since other tags have the same assets
    done
    sleep 3

    Popd
}

IsEmptyString() {
    local name="$1"
    local value="${!name}"
    test -n "$value" || DIE "$ASSETS_CONF: error: '$name' is empty."
}
DirExists() {
    local name="$1"
    local value="${!name}"
    test -d "$value" || DIE "$ASSETS_CONF: error: folder '$name' does not exist."
}

ShowPrompt() {
    printf2 "%-35s : " "$1"
}

RationalityTests()
{
    ShowPrompt "Checking values in $ASSETS_CONF"

    IsEmptyString ASSETSDIR
    IsEmptyString PKGBUILD_ROOTDIR
    IsEmptyString GITDIR
    IsEmptyString PKGNAMES
    IsEmptyString REPONAME
    IsEmptyString RELEASE_TAGS
    IsEmptyString SIGNER
    DirExists ASSETSDIR
    DirExists PKGBUILD_ROOTDIR
    DirExists GITDIR

    # make sure .git symlink exists
    test -e "$ASSETSDIR"/.git || ln -s "$GITDIR"/.git "$ASSETSDIR"

    test "$GITDIR"/.git -ef "$ASSETSDIR"/.git || \
        DIE "$ASSETS_CONF: error: folder '$ASSETSDIR/.git' differs from '$GITDIR/.git'."

    echo2 "done."
}

RunHooks()
{
    if [ -n "$ASSET_HOOKS" ] ; then
        ShowPrompt "Running asset hooks"
        local xx
        for xx in "${ASSET_HOOKS[@]}" ; do
            $xx
        done
        echo2 "done."
    fi
}

CompareWithAUR()  # compare certain AUR PKGBUILDs to local counterparts
{
    local xx
    local pkgdirname pkgname
    local vaur vlocal

    IsEmptyString AUR_PKGNAMES

    Pushd "$PKGBUILD_ROOTDIR"
    echo2 "Comparing certain packages to AUR..."
    for xx in "${AUR_PKGNAMES[@]}" ; do
        pkgdirname="$(ListNameToPkgName "$xx" yes)"
        test -n "$pkgdirname" || DIE "converting or fetching '$xx' failed"

        printf2 "    %-15s : " "$pkgdirname"

        # get versions from latest AUR PKGBUILDs
        vaur="$(PkgBuildVersion "$PKGBUILD_ROOTDIR/$pkgdirname")"
        test -n "$vaur" || DIE "PkgBuildVersion for '$pkgdirname' failed"

        # get current versions from local asset files
        pkgname="$(PkgBuildName "$pkgdirname")"
        vlocal="$(LocalVersion "$ASSETSDIR/$pkgname")"
        test -n "$vlocal" || DIE "LocalVersion for '$pkgname' failed"

        # compare versions
        if [ $(vercmp "$vaur" "$vlocal") -gt 0 ] ; then
            echo2 "update (aur=$vaur local=$vlocal)"
        else
            test "$vaur" = "$vlocal" && echo2 "OK ($vaur)" || echo2 "OK (aur=$vaur local=$vlocal)"
        fi
    done
    Popd
}

#### Global variables:

ASSETS_CONF=./assets.conf

#### Usage: $0 [--checkaur]
####     --checkaur    Compare certain AUR PKGBUILDs to local counterparts.


Main()
{
    test -r $ASSETS_CONF || DIE "cannot find local file $ASSETS_CONF"

    source $ASSETS_CONF         # local variables (with CAPITAL letters)

    RationalityTests            # check validity of values in $ASSETS_CONF
    RunHooks                    # may/should update local PKGBUILDs
    Assets_clone                # offer getting assets from github instead of using local ones

    if [ "$1" = "--checkaur" ] ; then
        # Simply compare some packages with AUR. Build nothing.
        CompareWithAUR
        return
    fi

    # Check if we need to build new versions of packages.
    # To do that, we compare local asset versions to PKGBUILD versions.
    # Note that
    #   - Assets_clone above may have downloaded local assets from github (if user decides it is necessary)
    #   - RunHooks     above may/should have updated local PKGBUILDs

    local removable=()          # collected
    local removableassets=()    # collected
    local built=()              # collected
    local signed=()             # collected
    declare -A newv oldv
    local tmp
    local xx pkg
    local pkgdirname            # dir name for a package
    local pkgname
    local buildsavedir          # tmp storage for built packages

    echo2 "Finding package info ..."

    Pushd "$PKGBUILD_ROOTDIR"
    for xx in "${PKGNAMES[@]}" ; do
        pkgdirname="$(ListNameToPkgName "$xx" yes)"
        test -n "$pkgdirname" || DIE "converting or fetching '$xx' failed"

        # get versions from latest PKGBUILDs
        tmp="$(PkgBuildVersion "$PKGBUILD_ROOTDIR/$pkgdirname")"
        test -n "$tmp" || DIE "PkgBuildVersion for '$xx' failed"
        newv["$pkgdirname"]="$tmp"

        # get current versions from local asset files
        pkgname="$(PkgBuildName "$pkgdirname")"
        tmp="$(LocalVersion "$ASSETSDIR/$pkgname")"
        test -n "$tmp" || DIE "LocalVersion for '$xx' failed"
        oldv["$pkgdirname"]="$tmp"
        echo2 "    $pkgdirname"
    done
    Popd

    # build if newer versions exist. When building, collect removables and builds.
    buildsavedir=$(mktemp -d "$HOME/.tmpdir.XXXXX")
    echo2 "Check if building is needed..."
    for xx in "${PKGNAMES[@]}" ; do
        pkgdirname="$(ListNameToPkgName "$xx" no)"
        if [ $(vercmp "${newv["$pkgdirname"]}" "${oldv["$pkgdirname"]}") -gt 0 ] ; then
            echo2 "building '$pkgdirname' ..."

            # old pkg
            pkgname="$(PkgBuildName "$pkgdirname")"
            pkg="$(ls -1 "$ASSETSDIR/$pkgname"-*.pkg.tar.xz 2> /dev/null)"
            test -n "$pkg" && {
                removable+=("$pkg")
                removable+=("$pkg".sig)
                removableassets+=("$(basename "$pkg")")
                removableassets+=("$(basename "$pkg")".sig)
            }

            # new pkg
            pkg="$(Build "$pkgdirname" "$buildsavedir" "$PKGBUILD_ROOTDIR/$pkgdirname")"
            case "$pkg" in
                "") DIE "$pkgdirname: build failed." ;;
                *)  built+=("$pkg")               ;;
            esac
        fi
    done

    if [ -n "$built" ] ; then

        # We have something built to be sent to github.
        
        echo2 "Signing and putting it all together..."

        # sign built packages
        for pkg in "${built[@]}" ; do
            gpg --local-user "$SIGNER" \
                --output "$pkg.sig" \
                --detach-sign "$pkg" || DIE "signing '$pkg' failed"
            signed+=("$pkg.sig")
        done

        # now we have: removable (and removableassets), built and signed

        # Move built and signed to assets dir...
        mv -i "${built[@]}" "${signed[@]}" "$ASSETSDIR"

        # ...and fix the variables 'built' and 'signed' accordingly.
        tmp=("${built[@]}")
        built=()
        for xx in "${tmp[@]}" ; do
            built+=("$ASSETSDIR/$(basename "$xx")")
        done
        tmp=("${signed[@]}")
        signed=()
        for xx in "${tmp[@]}" ; do
            signed+=("$ASSETSDIR/$(basename "$xx")")
        done

        # Put changed assets (built) to db.
        repo-add "$ASSETSDIR/$REPONAME".db.tar.xz "${built[@]}"
        rm -f "$ASSETSDIR/$REPONAME".{db,files}.tar.xz.old
        rm -f "$ASSETSDIR/$REPONAME".{db,files}
        cp -a "$ASSETSDIR/$REPONAME".db.tar.xz    "$ASSETSDIR/$REPONAME".db
        cp -a "$ASSETSDIR/$REPONAME".files.tar.xz "$ASSETSDIR/$REPONAME".files

        echo2 "Final stop before syncing with github!"
        read -p "Continue (Y/n)? " xx
        case "$xx" in
            [yY]*|"") ;;
            *) return ;;
        esac

        # Remove old assets (removable) from github and local folder.
        if [ -n "$removable" ] ; then
            rm -f  "${removable[@]}"
            for tag in "${RELEASE_TAGS[@]}" ; do
                delete-release-assets "$tag" "${removableassets[@]}" || WARN "removing assets with tag '$tag' failed"
                sleep 3
            done
            sleep 2
        fi

        # transfer assets (built, signed and db) to github
        for tag in "${RELEASE_TAGS[@]}" ; do
            add-release-assets "$tag" \
                               "${built[@]}" "${signed[@]}" "$ASSETSDIR/$REPONAME".{db,files}{,.tar.xz} || \
                DIE "adding assets with tag 'tag' failed"
        done
    else
        echo2 "Nothing to do."
    fi
}

Main "$@"
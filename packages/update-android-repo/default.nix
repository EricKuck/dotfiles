{
  writeShellApplication,
  curl,
  git,
  gnugrep,
  gnused,
  coreutils,
}:

writeShellApplication {
  name = "update-android-repo";
  runtimeInputs = [
    curl
    git
    gnugrep
    gnused
    coreutils
  ];
  text = ''
    repo_dir="$(git rev-parse --show-toplevel)/modules/darwin/gha-runner/android-repo"
    dest="$repo_dir/repository2-3.xml"

    update() {
      local url=$1 file=$2
      curl -fsS "$url" -o "$file.new"
      if cmp -s "$file.new" "$file"; then
        rm "$file.new"
        echo "$(basename "$file") already up to date."
      else
        mv "$file.new" "$file"
        echo "Updated $file -- commit it to pin the new manifest."
      fi
    }

    update https://dl.google.com/android/repository/repository2-3.xml "$dest"
    update https://dl.google.com/android/repository/sys-img/android/sys-img2-3.xml "$repo_dir/sys-img2-3.xml"

    echo
    echo "Newest stable SDK platforms now available to platformVersions:"
    grep -o 'path="platforms;android-[0-9][^"]*"' "$dest" \
      | sed 's/.*android-//; s/"$//' \
      | grep -v -- '-' \
      | sort -V \
      | tail -5 \
      | sed 's/^/  /'
  '';
}

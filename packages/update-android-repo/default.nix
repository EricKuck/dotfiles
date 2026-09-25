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
    dest="$(git rev-parse --show-toplevel)/modules/darwin/gha-runner/android-repo/repository2-3.xml"

    curl -fsS https://dl.google.com/android/repository/repository2-3.xml -o "$dest.new"
    if cmp -s "$dest.new" "$dest"; then
      rm "$dest.new"
      echo "Already up to date."
    else
      mv "$dest.new" "$dest"
      echo "Updated $dest -- commit it to pin the new manifest."
    fi

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

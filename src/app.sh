function echo_app_tag () {
	expect_vars HALCYON_DIR

	local ghc_tag sandbox_tag app_label app_magic_hash
	expect_args ghc_tag sandbox_tag app_label app_magic_hash -- "$@"

	local os ghc_version ghc_magic_hash constraints_hash sandbox_magic_hash
	os=$( detect_os ) || die
	ghc_version=$( echo_ghc_version "${ghc_tag}" ) || die
	ghc_magic_hash=$( echo_ghc_magic_hash "${ghc_tag}" ) || die
	constraints_hash=$( echo_sandbox_constraints_hash "${sandbox_tag}" ) || die
	sandbox_magic_hash=$( echo_sandbox_magic_hash "${sandbox_tag}" ) || die

	echo -e "${os}\t${HALCYON_DIR}\tghc-${ghc_version}\t${ghc_magic_hash}\t${constraints_hash}\t${sandbox_magic_hash}\t${app_label}\t${app_magic_hash}"
}


function echo_app_os () {
	local app_tag
	expect_args app_tag -- "$@"

	awk -F$'\t' '{ print $1 }' <<<"${app_tag}"
}


function echo_app_label () {
	local app_tag
	expect_args app_tag -- "$@"

	awk -F$'\t' '{ print $7 }' <<<"${app_tag}"
}


function echo_app_magic_hash () {
	local app_tag
	expect_args app_tag -- "$@"

	awk -F$'\t' '{ print $8 }' <<<"${app_tag}"
}


function echo_app_id () {
	local app_tag
	expect_args app_tag -- "$@"

	local app_label magic_hash
	app_label=$( echo_app_label "${app_tag}" ) || die
	magic_hash=$( echo_app_magic_hash "${app_tag}" ) || die

	echo "${app_label}${magic_hash:+~${magic_hash:0:7}}"
}


function echo_app_description () {
	local app_tag
	expect_args app_tag -- "$@"

	local app_id
	app_id=$( echo_app_id "${app_tag}" ) || die

	echo "${app_id}"
}


function echo_app_archive_name () {
	local app_tag
	expect_args app_tag -- "$@"

	local ghc_id sandbox_id app_id
	ghc_id=$( echo_ghc_id "${app_tag}" ) || die
	sandbox_id=$( echo_sandbox_id "${app_tag}" ) || die
	app_id=$( echo_app_id "${app_tag}" ) || die

	echo "halcyon-app-ghc-${ghc_id}-${sandbox_id}-${app_id}.tar.gz"
}


function detect_app_package_description () {
	local sources_dir
	expect_args sources_dir -- "$@"
	expect_existing "${sources_dir}"

	local package_file
	if ! package_file=$(
		find_spaceless_recursively "${sources_dir}" -maxdepth 1 -name '*.cabal' |
		match_exactly_one
	); then
		die 'Expected exactly one app package description'
	fi

	cat "${sources_dir}/${package_file}"
}


function detect_app_name () {
	local sources_dir
	expect_args sources_dir -- "$@"

	local app_name
	if ! app_name=$(
		detect_app_package_description "${sources_dir}" |
		awk '/^ *[Nn]ame:/ { print $2 }' |
		tr -d '\r' |
		match_exactly_one
	); then
		die 'Expected exactly one name in app package description'
	fi

	echo "${app_name}"
}


function detect_app_version () {
	local sources_dir
	expect_args sources_dir -- "$@"

	local app_version
	if ! app_version=$(
		detect_app_package_description "${sources_dir}" |
		awk '/^ *[Vv]ersion:/ { print $2 }' |
		tr -d '\r' |
		match_exactly_one
	); then
		die 'Expected exactly one version in app package description'
	fi

	echo "${app_version}"
}


function detect_app_executable () {
	local sources_dir
	expect_args sources_dir -- "$@"

	local app_executable
	if ! app_executable=$(
		detect_app_package_description "${sources_dir}" |
		awk '/^ *[Ee]xecutable / { print $2 }' |
		tr -d '\r' |
		match_exactly_one
	); then
		die 'Expected exactly one executable in app package description'
	fi

	echo "${app_executable}"
}


function detect_app_label () {
	local sources_dir
	expect_args sources_dir -- "$@"

	local app_name app_version
	app_name=$( detect_app_name "${sources_dir}" | sed 's/^halcyon-fake-//' ) || die
	app_version=$( detect_app_version "${sources_dir}" ) || die

	echo "${app_name}-${app_version}"
}


function validate_app_tag () {
	expect_vars HALCYON_DIR

	local app_tag
	expect_args app_tag -- "$@"

	if ! [ -f "${HALCYON_DIR}/app/.halcyon-tag" ]; then
		return 1
	fi

	local candidate_tag
	candidate_tag=$( match_exactly_one <"${HALCYON_DIR}/app/.halcyon-tag" ) || die
	if [ "${candidate_tag}" != "${app_tag}" ]; then
		return 1
	fi
}


function validate_app_magic () {
	local magic_hash
	expect_args magic_hash -- "$@"

	local candidate_hash
	candidate_hash=$( hash_spaceless_recursively "${HALCYON_DIR}/app/.halcyon-magic" -name 'app-*' ) || die
	if [ "${candidate_hash}" != "${magic_hash}" ]; then
		return 1
	fi
}


function validate_app () {
	local app_tag
	expect_args app_tag -- "$@"

	local magic_hash
	magic_hash=$( echo_app_magic_hash "${app_tag}" ) || die
	if ! validate_app_tag "${app_tag}" || ! validate_app_magic "${magic_hash}"; then
		return 1
	fi
}


function build_app () {
	expect_vars HALCYON_DIR
	expect_existing "${HALCYON_DIR}/ghc/.halcyon-tag" "${HALCYON_DIR}/sandbox/.halcyon-tag"

	local app_tag sources_dir
	expect_args app_tag sources_dir -- "$@"

	local ghc_tag sandbox_tag
	ghc_tag=$( <"${HALCYON_DIR}/ghc/.halcyon-tag" ) || die
	sandbox_tag=$( <"${HALCYON_DIR}/sandbox/.halcyon-tag" ) || die

	log 'Starting to build app layer'

	# TODO: insert run-time deps here

	if [ -f "${sources_dir}/.halcyon-magic/app-prebuild-hook" ]; then
		log 'Running app pre-build hook'
		( "${sources_dir}/.halcyon-magic/app-prebuild-hook" "${ghc_tag}" "${sandbox_tag}" "${app_tag}" "${sources_dir}" ) |& quote || die
	fi

	log 'Building app'

	cabal_build_app "${HALCYON_DIR}/sandbox" "${app_dir}" || die

	if [ -f "${sources_dir}/.halcyon-magic/app-postbuild-hook" ]; then
		log 'Running app post-build hook'
		( "${sources_dir}/.halcyon-magic/app-postbuild-hook" "${ghc_tag}" "${sandbox_tag}" "${app_tag}" "${sources_dir}" ) |& quote || die
	fi

	echo "${app_tag}" >"${app_dir}/.halcyon-tag" || die

	log 'Finished building app layer'
}


function archive_app () {
	expect_vars HALCYON_DIR HALCYON_CACHE_DIR HALCYON_NO_ARCHIVE
	expect_existing "${HALCYON_DIR}/app/.halcyon-tag"

	if (( HALCYON_NO_ARCHIVE )); then
		return 0
	fi

	local app_tag os app_archive
	app_tag=$( <"${HALCYON_DIR}/app/.halcyon-tag" ) || die
	os=$( echo_app_os "${app_tag}" ) || die
	app_archive=$( echo_app_archive_name "${app_tag}" ) || die

	log 'Archiving app layer'

	rm -f "${HALCYON_CACHE_DIR}/${app_archive}" || die
	tar_archive "${HALCYON_DIR}/app" "${HALCYON_CACHE_DIR}/${app_archive}" || die
	if ! upload_layer "${HALCYON_CACHE_DIR}/${app_archive}" "${os}"; then
		log_warning 'Cannot upload app layer archive'
	fi
}


function restore_app () {
	expect_vars HALCYON_DIR HALCYON_CACHE_DIR

	local app_tag
	expect_args app_tag -- "$@"

	local os app_archive
	os=$( echo_app_os "${app_tag}" ) || die
	app_archive=$( echo_app_archive_name "${app_tag}" ) || die

	if validate_app "${app_tag}"; then
		touch -c "${HALCYON_CACHE_DIR}/${app_archive}" || true
		log 'Using existing app layer'
		return 0
	fi
	rm -rf "${HALCYON_DIR}/app" || die

	log 'Restoring app layer'

	if ! [ -f "${HALCYON_CACHE_DIR}/${app_archive}" ] ||
		! tar_extract "${HALCYON_CACHE_DIR}/${app_archive}" "${HALCYON_DIR}/app" ||
		! validate_app "${app_tag}"
	then
		rm -rf "${HALCYON_CACHE_DIR}/${app_archive}" "${HALCYON_DIR}/app" || die
		if ! download_layer "${os}" "${app_archive}" "${HALCYON_CACHE_DIR}"; then
			log 'Cannot download app layer archive'
			return 1
		fi

		if ! tar_extract "${HALCYON_CACHE_DIR}/${app_archive}" "${HALCYON_DIR}/app" ||
			! validate_app "${app_tag}"
		then
			rm -rf "${HALCYON_CACHE_DIR}/${app_archive}" "${HALCYON_DIR}/app" || die
			log_warning 'Cannot extract app layer archive'
			return 1
		fi
	else
		touch -c "${HALCYON_CACHE_DIR}/${app_archive}" || true
	fi
}


function determine_app_tag () {
	local sources_dir
	expect_args sources_dir -- "$@"

	log_begin 'Determining app magic hash...            '

	local magic_hash
	magic_hash=$( hash_spaceless_recursively "${sources_dir}/.halcyon-magic" -name 'app-*' ) || die
	if [ -z "${magic_hash}" ]; then
		log_end '(none)'
	else
		log_end "${magic_hash:0:7}"
	fi

	log_begin 'Determining app label...                 '

	local app_label
	app_label=$( detect_app_label "${sources_dir}" ) || die

	log_end "${app_label}"

	local ghc_tag sandbox_tag app_tag
	ghc_tag=$( <"${HALCYON_DIR}/ghc/.halcyon-tag" ) || die
	sandbox_tag=$( <"${HALCYON_DIR}/sandbox/.halcyon-tag" ) || die

	echo_app_tag "${ghc_tag}" "${sandbox_tag}" "${app_label}" "${magic_hash}" || die
}


function install_app () {
	expect_vars HALCYON_DIR HALCYON_BUILD_APP HALCYON_NO_BUILD

	local app_dir
	expect_args app_dir -- "$@"
	expect_existing "${app_dir}"

	# TODO: change the install dir
	local install_dir
	install_dir="${HALCYON_DIR}/app"

	local app_tag app_description
	app_tag=$( determine_app_tag "${app_dir}" ) || die
	app_description=$( echo_app_description "${app_tag}" ) || die

	local restored_app
	restored_app=0
	if ! (( HALCYON_BUILD_APP )) && restore_app "${app_dir}" "${app_tag}"; then
		restored_app=1
	fi

	if (( HALCYON_BUILD_APP )) || (( ${HALCYON_CONFIGURE_APP:-0} )) || ! (( restored_app )); then
		if ! (( HALCYON_BUILD_APP )) && (( HALCYON_NO_BUILD )); then
			log_warning 'Cannot build app layer'
			return 1
		fi

		log 'Configuring app'

		cabal_configure_app "${HALCYON_DIR}/sandbox" "${app_dir}" --prefix="${install_dir}" || die
	else
		log 'Using restored app configuration'
	fi

	local built_app
	built_app=0
	if (( HALCYON_BUILD_APP )) || ! (( HALCYON_NO_BUILD )); then
		build_app "${app_dir}" "${app_tag}" || die
		archive_app "${app_dir}" || die
		built_app=1
	fi

	if ! (( restored_app )) && ! (( built_app )); then
		log_warning 'Cannot install app layer'
		return 1
	fi

	log 'Installing app'

	# NOTE: We extend PATH to avoid confusing the user with a spurious Cabal warning, such as:
	# "Warning: The directory .../bin is not in the system search path."

	PATH="${HALCYON_TMP_DEPLOY_DIR}${install_dir}/bin:${PATH}" \
		cabal_copy_app "${HALCYON_DIR}/sandbox" "${app_dir}" --destdir="${HALCYON_TMP_DEPLOY_DIR}" || die

	log 'App layer installed:'
	log_indent "${app_description}"
}

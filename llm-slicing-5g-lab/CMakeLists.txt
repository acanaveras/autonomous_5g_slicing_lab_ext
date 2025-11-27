add_executable(xapp_mac_ctrl
  mac_ctrl.c
  ../../../../src/util/alg_ds/alg/defer.c
  )

 target_link_libraries(xapp_mac_ctrl
 						PUBLIC
 						e42_xapp
 						-pthread
 						-lsctp
 						-ldl
 						)

# Commenting out xapp_rc_slice_ctrl target - source file does not exist
# add_executable(xapp_rc_slice_ctrl
# 	xapp_rc_slice_ctrl.c
# 	../../../../src/util/alg_ds/alg/defer.c
# 	)

add_executable(xapp_rc_slice_dynamic
		xapp_rc_slice_dynamic.c
		../../../../src/util/alg_ds/alg/defer.c
)

# Commenting out linking for non-existent xapp_rc_slice_ctrl target
# target_link_libraries(xapp_rc_slice_ctrl
# 											PUBLIC
# 											e42_xapp
# 											-pthread
# 											-lsctp
# 											-ldl
# 											)

target_link_libraries(xapp_rc_slice_dynamic
		PUBLIC
		e42_xapp
		-pthread
		-lsctp
		-ldl
)


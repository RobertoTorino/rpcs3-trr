add_library(3rdparty_qt5 INTERFACE)

# Prefer Qt6 for modern builds, but keep Qt5 fallback for older environments.
find_package(Qt6 6.2 CONFIG COMPONENTS Widgets Concurrent Gui QUIET)

if(Qt6Widgets_FOUND)
	set(RPCS3_QT_MAJOR 6)

	if(WIN32)
		target_link_libraries(3rdparty_qt5 INTERFACE Qt6::Widgets Qt6::Concurrent Qt6::Gui)
	else()
		find_package(Qt6 6.2 COMPONENTS DBus QUIET)
		if(Qt6DBus_FOUND)
			target_link_libraries(3rdparty_qt5 INTERFACE Qt6::Widgets Qt6::DBus Qt6::Concurrent Qt6::Gui)
			target_compile_definitions(3rdparty_qt5 INTERFACE -DHAVE_QTDBUS)
		else()
			target_link_libraries(3rdparty_qt5 INTERFACE Qt6::Widgets Qt6::Concurrent Qt6::Gui)
		endif()
	endif()

	if(DEFINED Qt6_DIR)
		set(RPCS3_QT_DEPLOY_ROOT "${Qt6_DIR}/../../../bin")
	endif()
else()
	find_package(Qt5 5.14 CONFIG COMPONENTS Widgets Concurrent REQUIRED)
	set(RPCS3_QT_MAJOR 5)

	if(WIN32)
		find_package(Qt5 5.14 COMPONENTS WinExtras REQUIRED)
		target_link_libraries(3rdparty_qt5 INTERFACE Qt5::Widgets Qt5::WinExtras Qt5::Concurrent)
		target_compile_definitions(3rdparty_qt5 INTERFACE -DHAVE_QT_WINEXTRAS)
	else()
		find_package(Qt5 5.14 COMPONENTS DBus Gui)
		if(Qt5DBus_FOUND)
			target_link_libraries(3rdparty_qt5 INTERFACE Qt5::Widgets Qt5::DBus Qt5::Concurrent)
			target_compile_definitions(3rdparty_qt5 INTERFACE -DHAVE_QTDBUS)
		else()
			target_link_libraries(3rdparty_qt5 INTERFACE Qt5::Widgets Qt5::Concurrent)
		endif()
		target_include_directories(3rdparty_qt5 INTERFACE ${Qt5Gui_PRIVATE_INCLUDE_DIRS})
	endif()

	if(DEFINED Qt5_DIR)
		set(RPCS3_QT_DEPLOY_ROOT "${Qt5_DIR}/../../../bin")
	endif()
endif()

if(NOT DEFINED RPCS3_QT_DEPLOY_ROOT)
	message(FATAL_ERROR "Could not determine Qt deploy tool location (RPCS3_QT_DEPLOY_ROOT).")
endif()

set(RPCS3_QT_DEPLOY_ROOT "${RPCS3_QT_DEPLOY_ROOT}" CACHE INTERNAL "Qt deploy tool root for RPCS3")

add_library(3rdparty::qt5 ALIAS 3rdparty_qt5)

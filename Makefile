
.PHONY: all clean devi-build devi-run devi-run-local

XBUILD=_DerivedData

# https://developer.apple.com/library/archive/technotes/tn2339/_index.html
# xcodebuild -list -project <your_project_name>.xcodeproj
xcode:
	xcodebuild -project objc-nativews.xcodeproj -scheme objc-nativews -configuration Release build -derivedDataPath _DerivedData

#$(BUILD):
#	@mkdir -p ${BUILD}

clean:
	-rm -rf ${XBUILD}


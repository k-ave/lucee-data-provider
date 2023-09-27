<cfscript>
	lstValidVersionTypes = "releases,snapshots,rc,beta,abc";
	lstVersionTypes = "releases,snapshots,rc,beta";
	lstVersionExtensionTypes = "release,abc,snapshot";

	param name="url.type" default="releases";
	url.type = !listFind(lstValidVersionTypes, url.type) ? "releases" : url.type;

	// TODO: Should be done in REST?
	aryVersionsToIgnore = [
		'05.003.007.0044.100'
	];
	aryExtensionsToIgnore = [
		'1E12B23C-5B38-4764-8FF41B7FD9428468'
	];

	stcLang = {
		desc: {
			abc: "Beta and Release Candidates are a preview for upcoming versions and not ready for production environments.",
			beta: "Beta are a preview for upcoming versions and not ready for production environments.",
			rc: "Release Candidates are candidates to get ready for production environments.",
			releases: "Releases are ready for production environments.",
			snapshots: "Snapshots are generated automatically with every push to the repository. Snapshots can be unstable are NOT recommended for production environments."
		},
		express: "The Express version is an easy to setup version which does not need to be installed. Just extract the zip file onto your computer and without further installation you can start by executing the corresponding start file. This is especially useful if you would like to get to know Lucee or want to test your applications under Lucee. It is also useful for use as a development environment.",
		war: 'Java Servlet engine Web ARchive',
		core: 'The Lucee Core file, you can simply copy this to the "patches" folder of your existing Lucee installation.',
		dependencies: 'Dependencies (3 party bundles) Lucee needs for this release, simply copy this to "/lucee-server/bundles" of your installation (If this files are not present Lucee will download them).',
		jar: 'Lucee jar file without dependencies Lucee needs to run. Simply copy this file to your servlet engine lib folder (classpath). If dependecy bundles are not in place Lucee will download them.',
		luceeAll: 'Lucee jar file that contains all dependencies Lucee needs to run. Simply copy this file to your servlet engine lib folder (classpath)',
		lib: "The Lucee Jar file, you can simply copy to your existing installation to update to Lucee 5. This file comes in 2 favors, the ""lucee.jar"" that only contains Lucee itself and no dependecies (Lucee will download dependencies if necessary) or the lucee-all.jar with all dependencies Lucee needs bundled (not availble for versions before 5.0.0.112).",
		libNew: "The Lucee Jar file, you can simply copy to your existing installation to update to Lucee 5. This file comes with all necessary dependencies Lucee needs build in, so no addional jars necessary. You can have this Jar in 2 flavors, a version containing all Core Extension (like Hibernate, Lucene or Axis) and a version with no Extension bundled.",
		installer: {
			win: "Windows",
			lin64: "Linux (64b)",
			lin32: "Linux (32b)"
		},
		singular: {
			releases: "Release",
			snapshots: "Snapshot",
			abc: 'RC / Beta',
			beta: 'Beta',
			rc: 'RC',
			ext: "Release",
			extsnap: "Snapshot",
			extabc: 'RC / Beta'
		},
		multi: {
			release: "Releases",
			snapshot: "Snapshots",
			abc: 'RCs / Betas',
			beta: 'Betas',
			rc: 'Release Candidates'
		}
	}

	listURL = "https://release.lucee.org/rest/update/provider/list/";
	EXTENSION_PROVIDER = "https://extension.lucee.org/rest/extension/provider/info?withLogo=true&type=all";
	baseURL = "https://release.lucee.org/rest/update/provider/";
	cdnURL = "https://cdn.lucee.org/";
	cdnURLExt = "https://ext.lucee.org/";

	doS3 = {
		express : true,
		jar : true,
		lco : true,
		light : true,
		zero : true,
		war : true
	};

	/*
	// not used
	extcacheLiveSpanInMinutes = 1000;
	MAX = 1000;
	EXTENSION_DOWNLOAD = "https://extension.lucee.org/rest/extension/provider/{type}/{id}";
	*/

	// getting all the versions as a struct and sorting them by newest first
	sortDesc = (versions) => {
		var keys = structKeyArray(arguments.versions);
		var stcNew = [:];
		for(var i = arrayLen(keys); i > 0; i--) {
			stcNew[keys[i]] = arguments.versions[keys[i]];
		}
		return stcNew;
	}
	versions = sortDesc(getVersions(structKeyExists(url,"reset")));

	// add types - releases,snapshots,rc,beta
	structEach(versions, (key, value) => {
		// snapshots, rc, beta, alpha or none (release)
		var strVersionType = lCase(listLast(arguments.value.version, '-'));

		arguments.value['type'] = '';

		switch (strVersionType) {
			case 'snapshot':
				arguments.value.type = 'snapshots';
				break;
			case 'rc':
				arguments.value.type = 'rc';
				break;
			case 'beta':
				arguments.value.type = 'beta'
				break;
			case 'alpha':
				arguments.value.type = 'alpha';
				break;
			default:
				arguments.value.type = 'releases';
		}

		// version used as output in select option
		arguments.value['versionNoAppendix'] = arguments.value.version;
	});
</cfscript>

<!--- FUNCTIONS --->
<cfscript>
	function getExtensions(flush = false) localmode=true {
		if(!arguments.flush && !isNull(application.extInfo)) {
			return application.extInfo;
		}

		http url=EXTENSION_PROVIDER&"&flush="&arguments.flush result="http";
		if(isNull(http.status_code) || http.status_code!=200)
			throw "could not connect to extension provider (#ep#)";

		var data = deSerializeJson(http.fileContent, false);
		if (!structKeyExists( data, "meta" ) ) {
			systemOutput("error fetching extensions, falling back on cache", true);

			http url=EXTENSION_PROVIDER result="http";
			if(isNull(http.status_code) || http.status_code!=200)
				throw "could not connect to extension provider (#ep#)";

			data = deSerializeJson(http.fileContent, false);
			application.extInfo = data.extensions;
		} else {
			application.extInfo = data.extensions;
		}

		return application.extInfo;
	}

	function extractVersions(qry) localmode=true {
		// To make a call this function once per extension rather than three times
		var data = {
			"release": [:],
			"abc": [:],
			"snapshot": [:]
		}

		// first we get the current version
		// if(variables.isVersionType(arguments.type,arguments.qry.version)) {
		// 	data[arguments.qry.version]={'filename':arguments.qry.fileName,'date':arguments.qry.created};
		// }

		var _other = arguments.qry.older;
		var _otherName = arguments.qry.olderName;
		var _otherDate = arguments.qry.olderDate;

		var arrExt = [];
		loop array=_other index="local.i" item="local.version" {
			arrExt[i] = {
				'version' : version,
				'filename' : _otherName[i],
				'date' : _otherDate[i]
			}
		}

		// appends current into other because some current version is not newer.
		arrayAppend(arrExt, {
			'version' : arguments.qry.version,
			'filename' : arguments.qry.fileName,
			'date' : arguments.qry.created
		});

		// sorts by version
		arraySort(arrExt, function(e1, e2){
			return compare(variables.toSort(arguments.e2.version), variables.toSort(arguments.e1.version));
		});

		loop array=arrExt index="i" item="local.ext" {
			if (variables.isVersionType("release", ext.version)) {
				data.release[ext.version] = {
					'filename' : ext.filename,
					'date' : ext.date
				};
			} else if (variables.isVersionType("abc", ext.version)) {
				data.abc[ext.version] = {
					'filename' : ext.filename,
					'date' : ext.date
				};
			} else if (variables.isVersionType("snapshot", ext.version)) {
				data.snapshot[ext.version] = {
					'filename' : ext.filename,
					'date' : ext.date
				};
			}
		}
		return data;
	}

	function toSort(required String version) localmode=true {
		var listLength = listLen(arguments.version, "-");
		var arr = [];

		if (listLength == 3) {
			arr = listToArray(listDeleteAt(arguments.version, listLength, "-"), ".,-"); // ESAPI extension has 5 parameters
		} else {
			arr = listToArray(listFirst(arguments.version, "-"), ".");
		}

		var rtn = "";
		var i = "";
		var v = "";

		loop array=arr index="i" item="v" {
			if(len(v)<5) rtn&="."&repeatString("0",5-len(v))&v;
			else rtn&="."&v;
		}

		return rtn;
	}

	function isVersionType(type, val) localmode=true {
		if (arguments.type == "all" || arguments.type == "") {
			return true;
		}

		if (arguments.type == "snapshot") {
			return findNoCase('-SNAPSHOT', arguments.val);
		} else if (arguments.type == "abc") {
			if(findNoCase('-ALPHA', arguments.val) 
				|| findNoCase('-BETA', arguments.val)
				|| findNoCase('-RC', arguments.val)
			) {
				return true;
			}
			return false;
		} else if(arguments.type == "release") {
			if(!findNoCase('-ALPHA', arguments.val)
				&& !findNoCase('-BETA', arguments.val)
				&& !findNoCase('-RC', arguments.val)
				&& !findNoCase('-SNAPSHOT', arguments.val)
			) {
				return true;
			}
			return false;
		}
	}

	function getVersions(flush = false) {
		if(!arguments.flush && structKeyExists(application, "extVer")) {
			return application.extVer;
		}
		
		http url=listURL&"?extended=true"&(arguments.flush?"&flush=true":"") result="local.res";
		var versions = deserializeJson(res.fileContent);
		if ( isStruct(versions) && structKeyExists(versions, "message") ) {
			systemOutput("download page falling back on cached versions", true);
			http url=listURL&"?extended=true" result="local.res";
			versions = deserializeJson(res.fileContent);
		}

		application.extVer = versions;

		return application.extVer;
	}

	function getDate(version, flush = false) {
		if(!arguments.flush && !isNull(application.mavenDates[arguments.version])) {
			return application.mavenDates[arguments.version] ?: "";
		}

		var res = "";

		try{
			http url="https://release.lucee.org/rest/update/provider/getdate/"&arguments.version result="res" timeout="5";
			res = trim(deserializeJson(res.fileContent));
			application.mavenDates[arguments.version] = lsDateFormat(parseDateTime(res));
		} catch(e) {}

		if(len(res) == 0) {
			return "";
		}

		return application.mavenDates[arguments.version] ?: "";
	}

	function getInfo(version, flush = false) {
		if(!arguments.flush && !isNull(application.mavenInfo[arguments.version])) {
			return application.mavenInfo[arguments.version] ?: "";
		}

		var res = "";

		try{
			http url="https://release.lucee.org/rest/update/provider/info/"&arguments.version result="res";
			res = deserializeJson(res.fileContent);
			application.mavenInfo[arguments.version] = res;
		} catch(e) {}

		if(len(res) == 0) {
			return "";
		}

		return application.mavenInfo[arguments.version] ?: "";
	}

	function getChangelog(versionFrom, versionTo, flush = false) {
		var id = arguments.versionFrom&"-"&arguments.versionTo;
		if(!arguments.flush && !isNull(application.mavenChangeLog[id])) {
			return application.mavenChangelog[id] ?: "";
		}

		var res = "";

		//try{
			http url="https://release.lucee.org/rest/update/provider/changelog/"&arguments.versionFrom&"/"&arguments.versionTo result="res";
			var res = deserializeJson(res.fileContent);
			application.mavenChangeLog[id] = res;
		//}catch(e) {}

		if(len(res)==0) {
			return "";
		}

		return application.mavenChangeLog[id] ?: "";
	}
</cfscript>

<!DOCTYPE html>
<html>
	<head>
		<meta charset="utf-8">
		<meta content="ie=edge" http-equiv="x-ua-compatible">
		<meta content="initial-scale=1, shrink-to-fit=no, width=device-width" name="viewport">
		<title>Download Lucee</title>
		<link rel="shortcut icon" href="/res/images/logo.png">
		<link rel="apple-touch-icon" href="/res/images/logo.png">
		<link rel="apple-touch-icon" sizes="72x72" href="/res/images/logo.png">
		<link rel="apple-touch-icon" sizes="114x114" href="/res/images/logo.png">

		<script crossorigin="anonymous" integrity="sha384-KJ3o2DKtIkvYIK3UENzmM7KCkRr/rE9/Qpg6aAZGJwFDMVNA/GpGFF93hXpG5KkN" src="https://code.jquery.com/jquery-3.2.1.slim.min.js"></script>
		<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" integrity="sha384-BVYiiSIFeK1dGmJRAkycuHAHRg32OmUcww7on3RYdg4Va+PmSTsz/K68vbdEjh4u" crossorigin="anonymous">
		<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js" integrity="sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa" crossorigin="anonymous"></script>
		<link href="/res/download.css" rel="stylesheet">
		<script src="/res/download.js" defer></script>

		<script type="text/javascript">
			$(document).ready(function () {
				let isSafari = !!navigator.userAgent.match(/Version\/[\d\.]+.*Safari/)
				let isTouch = ('ontouchstart' in document.documentElement);
				let mthd = isTouch ? 'click' : 'mouseenter';

				$(".triggerIcon").popover({
					trigger: "hover",
					placement: "auto",
					position: "relative",
					html: true,
					animation:false
				})
				.on(mthd, function () {
					var _this = this;
					if (isSafari) {
						$('.popover').attr('style', 'max-width: 200px !important');
						$('.popover-title').attr('style', 'max-width: 100px !important');
					}
					$(this).popover("show");
				})
				.on("mouseleave touchmove", function () {
					var _this = this;
					setTimeout(function () {
						if (!$(".popover:hover").length) {
							$(_this).popover("hide");
						}
					})
				});

				$('.permalink').each(function() {
					let anchor = document.createElement('a');
					anchor.href = '#' + $(this).attr('data-id');
					$(this).wrapInner(anchor)
				});
				$('span.permalink').hide();
				$('div.permalinkHover').hover(
					function() { $(this).find('span.permalink').show(); },
					function() { $(this).find('span.permalink').hide(); }
				);
			});

			function hideData (a) {
				$('.'+a).removeClass('show');
				$('#'+a+'_id').show();
			}
			function hideToggle (a) {
				$('#'+a).hide();
			}
			function change(type,field,id) {
				window.location="?"+type+"="+field.value+"#"+id;
			}
		</script>

		<style rel="stylesheet">
			.data-content {
				background-color: #01798a;
				color: white;
				min-width: 100%;
				font-size: 14px;
				line-height: 15px;
			}
			.triggerIcon {
				color: #01798a !important;
				cursor: pointer;
			}
			.jumboStyle {
				padding: 0rem 0rem !important;
				border-radius: 0px !important;
				text-align: center !important;
			}
			.fontSize {
				font-size: 20px !important;
			}
			.BoxWidth {
				padding: 1rem 1rem 2rem 1rem;
				border-radius: 1%;
				padding-left: 6%;
			}
			.col-md-3 {
				padding-right: 8px !important;
				padding-left: 8px !important;
			}
			.desc {
				padding: 8px;
				vertical-align: top;
				font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";
				font-size: 1.5rem;
				font-weight: 400;
				line-height: 1.5;
				color: #212529;
				text-align: left;
			}
			.descDiv {
				min-height: 130px;
			}
			.installerDiv {
				min-height: 75px;
			}
			.jarDiv {
				min-height: 60px;
			}
			.divHeight {
				min-height: 36px;
			}
			.fontStyle {
				font-size: 16px !important;
				font-weight: normal !important;
			}
			.row_even {
				background-color: #ebebeb;
				padding: 1% 0 0 4%;
			}
			.row_odd {
				background-color: #dadada;
				padding: 1% 0 0 4%;
			}
			.borderInfo {
				border: 1px ridge #c7c7c7 !important;
				padding-left: 0px !important;
				padding-right: 0px !important;
				background-color: #ebebeb;
			}
			.well {
				background-color: white !important;
			}
			.popover-content {
				padding: 0.5px 0px !important;
			}
			.popover.bottom .arrow:after {
				border-bottom-color: #01798a !important;
			}
			.popover {
				border: 2px solid #01798a !important;
			}
			.popover-title {
				padding: 4px 8px !important;
			}
			.row_alterEven {
				background-color: #ebebeb;
				padding: 0% 0 0 4%;
			}
			.row_alterOdd {
				background-color: #dadada;
				padding: 0% 0 0 4%;
			}
			/*.TextStyle{ padding: 1%; font-family: "Segoe UI"; font-size: 1.25rem; font-weight: 600;}*/
			.TextStyle, .textStyle {
				padding: 1%;
				font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol" !important;
				font-size: 1.5rem !important;
				font-weight: normal !important;
			}
			.head1 {
				font-family: "Times New Roman", Times, serif;
				font-size: 2.5rem;
				font-weight: 503;
			}
			h2.fontSize {
				margin-bottom: -1.8rem !important;
			}
			.title {
				font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol" !important;
				font-size: 28px !important;
			}
			.textWrap {
				text-align: center;
				overflow: hidden;
				white-space: nowrap;
			}
			@media only screen and (max-width: 1200px) {
				.textWrap {
					text-align: center !important;
					overflow: auto !important;
					white-space: normal !important;
				}
			}
			@media only screen and (min-width: 1500px) {
				.textWrap {
					text-align: center !important;
					overflow: auto !important;
					white-space: normal !important;
				}
			}
		</style>
	</head>

	<body class="container py-3">
		<cfoutput>
			<div class="bg-primary jumbotron text-white">
				<h1 class="display-3">Downloads</h1>
				<p>Lucee Server and Extension downloads</p>
			</div>

			<h2>Lucee Server</h2>
			<p style="font-size: 1.6rem;">Lucee Release Announcements, including changelogs are available via <a href="https://dev.lucee.org/c/news/release/8">Releases Category</a></p>
			<p style="font-size: 1.6rem;">Extension updates and changelogs are posted under the <a href="https://dev.lucee.org/c/hacking/extensions/5">Extensions Category</a></p>
			<p style="font-size: 1.6rem;">Official Lucee Docker images are available via <a href="https://hub.docker.com/r/lucee/lucee">Docker Hub</a></p>
			<p style="font-size: 1.6rem;">Commandbox Lucee engines/releases are listed at <a href="https://www.forgebox.io/view/lucee">Forgebox</a></p>

			<cfset rows = {}>
			<cfset _versions = {}>

			<div class="panel" id="core">
				<div class="panel-body">
					<cfloop list="#lstVersionTypes#" item="versiontype">
						<cfset _versions[versiontype] = []>
						<div class="col-md-3 col-sm-3 col-xs-3">
							<!--- dropDown --->
							<div class="bg-primary BoxWidth text-white">

								<cfif !structKeyExists(url, versiontype)>
									<cfloop struct="#versions#" index="vs" item="data">
										<cfif data.type != versiontype>
											<cfcontinue>
										</cfif>
										<cfset url[versiontype] = vs>
										<cfset rows[versiontype] = vs>
										<cfbreak>
									</cfloop>
								</cfif>

								<h2><b>#stcLang.singular[versiontype]#</b></h2>
								<select onchange="change('#versiontype#',this, 'core')" style="color:##7f8c8d;font-style:normal;" id="lCore" class="form-control">
									<cfloop struct="#versions#" index="vs" item="data">

										<cfif data.type != versiontype OR arrayFind(aryVersionsToIgnore, vs)>
											<cfcontinue>
										</cfif>

										<cfset isSelected = url[versiontype] == vs ? true : false>

										<cfif isSelected>
											<cfset rows[versiontype] = vs>
										</cfif>

										<cfset arrayAppend(_versions[versiontype], data.version)>

										<option value="#vs#"#isSelected ? ' selected="selected"' : ''#>#data.versionNoAppendix#</option>
									</cfloop>
								</select>
							</div>

							<cfset dw = versions[rows[versiontype]]>

							<!--- desc --->
							<div class="desc descDiv row_even">
								<cfset res = getDate(dw.version)>
								<span style="font-weight:600">#dw.version#</span>
								<cfif len(res)>
									<span style="font-size:12px">(#res#)</span>
								</cfif><br><br>
								#stcLang.desc[versiontype]#
							</div>
							
							<!--- Express --->
							<cfif structKeyExists(dw,"express")>
								<div class="row_odd divHeight">
									<cfset uri = doS3.express ? "#cdnURL##dw.express#" : "#baseURL#express/#dw.version#">

									<div class="fontStyle">
										<a href="#uri#">Express</a>
										<span class="triggerIcon" title="#stcLang.express#">
											<span class="glyphicon glyphicon-info-sign"></span>
										</span>
									</div>
								</div>
							</cfif>

							<!--- Installer --->
							<div class="row_even installerDiv">
								<cfif versiontype == "releases">
									<cfif !structKeyExists(dw,"win")
										and !structKeyExists(dw,"lin32")
										and !structKeyExists(dw,"lin64")>

										<cfif left(dw.version,1) GT 4>
											<div class="fontStyle">
												<span class="text-primary">Coming Soon!</span>
												<span class="triggerIcon" title="Installers will available on soon">
													<span class="glyphicon glyphicon-info-sign"></span>
												</span>
											</div>
										</cfif>
									<cfelse>
										<cfset count=1>
										<cfset str="">

										<cfloop list="win,lin64,lin32" item="kk">
											<cfif !structKeyExists(dw,kk)>
												<cfcontinue>
											</cfif>

											<cfset uri="#cdnURL##dw[kk]#">
											<cfif count GT 1>
												<cfset str&='<br>'>
											</cfif>

											<cfset str &= '<a href="#uri#">#stcLang.installer[kk]# Installer</a>&nbsp;<span class="triggerIcon" title="#stcLang.installer[kk]# Installer"><span class="glyphicon glyphicon-info-sign"></span></span>'>
											<cfset count++>
										</cfloop>
										<div class="fontStyle">#str#</div>
									</cfif>
								</cfif>
							</div>

							<!--- jar --->
							<cfif structKeyExists(dw,"jar") OR structKeyExists(dw,"light") OR structKeyExists(dw,"zero")>
								<div class="row_odd jarDiv">
									<cfif structKeyExists(dw,"jar")>
										<cfset uri = doS3.jar ? "#cdnURL##dw.jar#" : "#baseURL#loader/#dw.version#">

										<div class="fontStyle">
											<a href="#(uri)#">lucee.jar</a>
											<span  class="triggerIcon" title="#stcLang.jar#">
												<span class="glyphicon glyphicon-info-sign"></span>
											</span>
										</div>
									</cfif>

									<cfif structKeyExists(dw,"light")>
										<cfset uri = doS3.light ? "#cdnURL##dw.light#" : "#baseURL#light/#dw.version#">

										<div class="fontStyle">
											<a href="#(uri)#">lucee-light.jar</a>
											<span  class="triggerIcon" title='Lucee Jar file without any Extensions bundled, "Lucee light"'>
												<span class="glyphicon glyphicon-info-sign"></span>
											</span>
										</div>
									</cfif>

									<cfif structKeyExists(dw,"zero")>
										<cfset uri = doS3.zero ? "#cdnURL##dw.zero#" : "#baseURL#zero/#dw.version#">

										<div class="fontStyle">
											<a href="#(uri)#">lucee-zero.jar</a>
											<span class="triggerIcon" title='Lucee Jar file without any Extensions bundled or doc and admin bundles, "Lucee zero"'>
												<span class="glyphicon glyphicon-info-sign"></span>
											</span>
										</div>
									</cfif>
								</div>
							</cfif>

							<!--- core --->
							<cfif structKeyExists(dw,"lco")>
								<div class="row_even divHeight">

									<cfset uri = doS3.lco ? "#cdnURL##dw.lco#" : "#baseURL#core/#dw.version#">

									<div class="fontStyle">
										<a href="#(uri)#">Core</a>
										<span class="triggerIcon" title='#stcLang.core#'>
											<span class="glyphicon glyphicon-info-sign"></span>
										</span>
									</div>
								</div>
							</cfif>

							<!--- WAR --->
							<cfif structKeyExists(dw,"war")>
								<div class="row_odd divHeight">

									<cfset uri = doS3.war ? "#cdnURL##dw.war#" : "#baseURL#war/#dw.version#">

									<div class="fontStyle">
										<a href="#(uri)#" title="#stcLang.war#">WAR</a>
										<span class="triggerIcon" title="#stcLang.war#">
											<span class="glyphicon glyphicon-info-sign"></span>
										</span>
									</div>
								</div>
							</cfif>

							<!--- logs --->
							<div class="row_even divHeight">

								<cfscript>
									loop array=_versions[versiontype] item="vv" index="i"{
										if(vv != dw.version ) {
											continue;
										}
										prevVersion = arrayIndexExists(_versions[versiontype],i+1)?_versions[versiontype][i+1]:"0.0.0.0";
									}

									changelog = getChangelog(prevVersion,dw.version);

									if(isStruct(changelog)) {
										structDelete(changelog,prevVersion);
									}
								</cfscript>

								<cfif isstruct(changelog) && structCount(changelog) GT 0>
									<div class="fontStyle">
										<p class="collapsed mb-0" data-toggle="modal" data-target="##myModal#versiontype#">Changelog<small class="align-middle h6 mb-0 ml-1"><i class="icon icon-collapse collapsed"></i></small></p>
									</div>
									<div class="modal fade" id="myModal#versiontype#" role="dialog">
										<div class="modal-dialog modal-lg">
											<div class="modal-content">
												<div class="modal-header">
													<button type="button" class="close" data-dismiss="modal">&times;</button>
													<h4 class="modal-title"><b>Version-#dw.version# Changelogs</b></h4>
												</div>
												<div class="modal-body desc">
													<cfset changelogTicketList = "">
													<cfloop struct="#changelog#" index="ver" item="tickets">
														<cfloop struct="#tickets#" index="id" item="subject">
															<cfif listFindNoCase(changelogTicketList, id)>
																<cfcontinue>
															</cfif>

															<cfset changelogTicketList = listAppend(changelogTicketList, id)>

															<a href="https://bugs.lucee.org/browse/#id#" target="blank">#id#</a>- #subject#<br>
														</cfloop>
													</cfloop>
												</div>
												<div class="modal-footer">
													<button type="button" class="btn btn-default btn-lg" data-dismiss="modal">Close</button>
												</div>
											</div>
										</div>
									</div>
								<cfelse>
									<div class="fontStyle"></div>
								</cfif>
							</div>
							<div><hr></div>
						</div>
					</cfloop>
				</div>
			</div>

			<cfset extQry = getExtensions(structKeyExists(url,"reset"))>
			<div id="ext">
				<h2>Extensions</h2>

				<p style="font-size: 1.7rem;font-weight:normal;">Lucee Extensions, simply copy them to /lucee-server/deploy, of a running Lucee installation, to install them. You can also install this Extensions from within your Lucee Administrator under "Extension/Application".</p>

				<cfloop query=extQry>

					<cfif arrayFind(aryExtensionsToIgnore, extQry.id)>
						<cfcontinue>
					</cfif>

					<div class="container">
						<div class="col-ms-12 col-xs-12 well well-sm">
							<!--- title --->
							<div class="permalinkHover"  id="#extQry.id#" >
								<span class="head1 title">#extQry.name#
									<span data-id="#extQry.id#" class="permalink">
										<img src="test.ico">
									</span>
								</span>
							</div>

							<hr>

							<!--- image --->
							<div class='col-xs-2 col-md-2'>
								<div>
									<cfif len(extQry.image)>
										<img style="max-width: 100%;" src="data:image/png;base64,#extQry.image#">
									</cfif>
								</div>
							</div>

							<!--- description --->
							<div class='col-md-10 col-xs-10'>
								<div class="container bg-white mb-2" style="margin-left:-1.7%;">
									<div class="head1 textStyle" style="font-size:2rem !important;"> 
										ID: #extQry.id# 
										<p class="fontStyle ml-2">#extQry.description#</p>
									</div>
								
									<!--- downloads --->
									<div class="row">
										<!--- call extractVersions function once per extension rather than three times --->
										<cfset exts = extractVersions(extQry)>

										<cfloop list="#lstVersionExtensionTypes#" item="versiontype">
											<cfif NOT structCount(exts[versiontype])>
												<cfcontinue>
											</cfif>

											<div class="mb-0 mt-1 col-xs-4 col-md-4 borderInfo">
												<div class="bg-primary jumbotron text-white jumboStyle">
													<span class="btn-primary">
														<h2 class="fontSize">#stcLang.multi[versiontype]#</h2>
													</span>
												</div>

												<cfset ind=0>
												<cfset uid="">
												<cfset cnt=structCount(exts[versiontype])>

												<cfloop struct="#exts[versiontype]#" index="ver" item="el">
													<cfset ind++>

													<!--- show more --->
													<cfif ind EQ 5 and cnt GT 6>
														<cfset uid = createUniqueId()>
														<div style="text-align:center;background-color:##BCBCBC;color:##2C3A47;" id="#uid#_release_id" class="collapse-toggle collapsed textStyle" onclick="return hideToggle('#uid#_release_id');"  data-toggle="collapse">
															<b><i>Show more..</i></b>
															<small class="align-middle h6 mb-0">
																<i class="icon icon-open"></i>
															</small>
														</div>
														<!--- div for 'show more/showless' --->
														<div class="clog-detail collapse #uid#_release row_alter" style="text-align:center;">
													</cfif>

													<!--- TODO: could be done with css nth/child --->
													<div class="textStyle textWrap row_alter<cfif ind MOD 2 eq 0>Even<cfelse>Odd</cfif>">
														<a href="#cdnURLExt##el.filename#">#ver# (#lsDateFormat(el.date)#)</a>
														<!---
															<span  class="triggerIcon" title="">
																<span class="glyphicon glyphicon-info-sign"></span>
															</span>
														--->
													</div>

													<!--- show less --->
													<cfif cnt EQ ind and len(uid)>
														<div class="showLess textStyle" style="text-align:center;background-color:##BCBCBC;cursor:pointer;" onclick="return hideData('#uid#_release');">
															<b><i>Show less</i></b>
															<small class="align-middle h6 mb-0  hideClick">
																<i class="icon icon-collapse"></i>
															</small>
														</div>
														<!--- div for 'show more/showless' --->
														</div>
													</cfif>
												</cfloop>
											</div>
										</cfloop>
									</div>
								</div>
							</div>
						</div>
					</div>
				</cfloop>
			</div>
		</cfoutput>
	</body>
</html>
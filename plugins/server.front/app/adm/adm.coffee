hooks = {}

hooks.configRoutes = ($routeProvider, $locationProvider) ->
	$routeProvider.when '/adm',
		templateUrl: '/adm/users-manager.html'
		controller: 'AdmUsersManagerCtrl'

hooks.config = ->

	app.factory 'AdmService', ($http, $rootScope, $cookieStore) ->
		$rootScope.accessToken = $cookieStore.get 'accessToken'
		api = apiRequest $http, $rootScope
		return {
			getUsers: (success, error) ->
				api 'adm/users', success, error

			getAppInfos : (id, success, error) ->
				api "adm/app/#{id}", success, error

			sendInvite: (id, success, error) ->
				api "adm/users/#{id}/invite", success, error, method:'post'

			removeUser: (id, success, error) ->
				api "adm/users/#{id}", success, error, method:'delete'

			stat: (opts, success, error) ->
				opts.unit ?= 'h'
				opts.start ?= new Date() - 24*3600*1000
				opts.end ?= (new Date).getTime()
				opts.start = Math.floor(opts.start/1000)
				opts.end = Math.floor(opts.end/1000)
				api "adm/stats/#{opts.stat}?unit=#{opts.unit}&start=#{opts.start}&end=#{opts.end}", success, error

			mailjetUpdate: (success, error) ->
				api "adm/update_mailjet", success, error

			rankingsUpdate: (success, error) ->
				api "adm/rankings/refresh", success, error

			getRanking: (data, success, error) ->
				if data.type == 'app'
					delete data.type
					api "adm/ranking/apps", success, error, method: "post", data: data
				else
					api "adm/ranking", success, error, method: "post", data: data

			getWishlist: (success, error) ->
				api 'adm/wishlist', success, error

			removeProvider: (name, success, error) ->
				api "adm/wishlist/#{name}", success, error, method:'delete'

			setProviderStatus: (name, status, success, error) ->
				api "adm/wishlist/#{name}/status/#{status}", success, error, method:'post'

			resetAllSecrets: (success, error) ->
				api "adm/secrets/reset", success, error

		}

	#################################
	# ADMIN USER MANAGER CONTROLLER #
	#################################
	app.controller 'AdmUsersManagerCtrl', ($scope, $rootScope, $timeout, $filter, $location, ProviderService, UserService, AdmService, MenuService, AppService) ->
		if not UserService.isLogin()
			$location.path '/signin'
			return

		MenuService.changed()
		$scope.info = {}

		# Home

		$scope.resetSecrets = ->
			if (confirm("Are you sure to reset all user's secrets keys ??"))
				AdmService.resetAllSecrets (-> alert("done")), (-> alert("error"))

		# Users list

		$scope.users = []
		$scope.nbUsers = 0
		$scope.nbUnvalidatedUser = 0

		countUnvalidatedUser = ()->
			$scope.nbUnvalidatedUser = 0
			for i of $scope.users
				if $scope.users[i].validated == '0'
					$scope.nbUnvalidatedUser++

		refreshUsersList = (users, page) ->
			$scope.users = users
			$scope.nbUsers = Object.size(users)

			array = []
			for i of $scope.users
				array.push $scope.users[i]

			countUnvalidatedUser()

			$scope.filtered = $filter('filter')(array, $scope.query)
			if (page)
				$scope.pagination =
					nbPerPage: 11
					nbPages: Math.ceil($scope.nbUsers / 10)
					current: page
					max: 5

			$scope.queryChange = ->
				$timeout (->
					$scope.filtered = $filter('filter')(array, $scope.query)
					$scope.pagination.nbPages = Math.ceil($scope.nbUsers / 10)
					$scope.pagination.current = page if page
				), 0

		AdmService.getUsers ((u)->refreshUsersList u.data,1), (error) -> console.log "error", error





		# Stats graphs

		$scope.chart = stat:'users', day:1

		displayStat = (stat, id, opts) ->
			opts ?= {}
			opts.stat = stat
			AdmService.stat opts, (res) ->
				chart = new Chart $("#" + id).get(0).getContext('2d')
				$scope.chart.total = res.data.total
				chart.Line
					labels: Object.keys(res.data.timeline)
					datasets: [
						fillColor : "rgba(151,187,205,0.5)"
						strokeColor : "rgba(151,187,205,1)"
						pointColor : "rgba(151,187,205,1)"
						pointStrokeColor : "#fff"
						data: (v for k,v of res.data.timeline)
					]

		displayStat 'users', 'chartCanevas'
		$scope.chartSubmit = ->
			if not $scope.chart.day
				$scope.chart.day = 1
			if $scope.chart.day <= 3
				unit = 'h'
			else if $scope.chart.day <= 93
				unit = 'd'
			else
				unit = 'm'
			displayStat $scope.chart.stat, 'chartCanevas',
				start: new Date() - 24*3600*1000*$scope.chart.day
				unit: unit

		$scope.mailjetUpdate = ->
			AdmService.mailjetUpdate (->), (err) -> alert err.message


		# Get user details
		$scope.getUserDetails = (user) ->
			$scope.info = {}
			$scope.noApp = true
			$scope.user = user
			$scope.apps = []
			$scope.noApp = false if user.apps.length > 0

			for i of user.apps
				AdmService.getAppInfos user.apps[i], ((app) ->
					$scope.apps.push(app.data)
				), (error) ->
					$scope.info = error

		$scope.removeUser = (user)->
			$scope.info = {}
			if confirm('are you sure to remove this user ?')
				AdmService.removeUser user.id, (->
					delete $scope.users[user.email]
					refreshUsersList $scope.users
				), (error) ->
					$scope.info = error

		# Send invitation request
		$scope.sendRequest = (user, cb) ->
			$scope.info = {}
			AdmService.sendInvite user.id, (->
				user.validated = '2'
				countUnvalidatedUser()
				if cb
					cb 0
			), (error) ->
				$scope.info = error
				if cb
					cb error




		$scope.inviteAllUsers = ->
			$scope.info = {}
			x = 0

			for user of $scope.users
				u = $scope.users[user]
				if u.validated == "0"
					console.log u
					$scope.sendRequest u
					x++
					if x >= 20
						break

		#
		# Rankings
		#
		$scope.ranking =
			target_names:
				'a:k':'Apps -> keys'
				'a:co':'Apps -> auth'
				'a:co:success':'Apps -> auth success'
				'a:co:error':'Apps -> auth error'
				'p:k':'Providers -> keys'
				'p:co':'Providers -> auth'
				'p:co:success':'Providers -> auth success'
				'p:co:error':'Providers -> auth error'
			unit_names: {'d':'Day', 'w':'Week', 'm':'Month', '':'All'}
			target: 'p:k'
			type: 'provider'
			unit: ''
		$scope.refreshRanking = ->
			opts = target:$scope.ranking.target
			if opts.target[0] == 'p'
				$scope.ranking.type = 'provider'
			else
				$scope.ranking.type = ''
			opts.unit = $scope.ranking.unit if $scope.ranking.unit
			opts.type = 'app' if not $scope.ranking.type
			AdmService.getRanking opts, (success) ->
				$scope.ranksFiltered = success.data
				$scope.ranksPagination =
					nbPerPage: 15
					nbPages: Math.ceil($scope.ranksFiltered.length / 15)
					current: 1
					max: 5

		$scope.refreshRanking()

		$scope.setRankingTarget = (target) ->
			$scope.ranking.target = target
			$scope.refreshRanking()

		$scope.setRankingUnit = (unit) ->
			$scope.ranking.unit = unit
			$scope.refreshRanking()

		$scope.rankingsUpdate = ->
			AdmService.rankingsUpdate (->), (err) -> alert err.message

		#
		# Providers
		#
		$scope.providers = []
		$scope.providersDetails = {}
		ProviderService.list (success) ->
			$scope.providersDetails = {}
			for p in success.data
				$scope.providers.push p.name
				$scope.providersDetails[p.name] = p
		$scope.providerQuery = name:'facebook'
		$scope.provider_ranking =
			name: 'facebook'
			target_names:
				'p:auth_array:[provider]':'Scopes auth'
				'p:auth_array:[provider]:success':'Scopes auth success'
				'p:auth_array:[provider]:error':'Scopes auth errors'
			target: 'p:auth_array:[provider]'
			unit: ''
		$scope.refreshProviderRanking = ->
			opts = target:$scope.provider_ranking.target.replace '[provider]', $scope.provider_ranking.name
			opts.unit = $scope.provider_ranking.unit if $scope.provider_ranking.unit
			AdmService.getRanking opts, (success) ->
				$scope.providerFiltered = success.data
				$scope.providerPagination =
					nbPerPage: 15
					nbPages: Math.ceil($scope.providerFiltered.length / 15)
					current: 1
					max: 5

		$scope.refreshProviderRanking()

		$scope.setProviderRankingTarget = (target) ->
			$scope.provider_ranking.target = target
			$scope.refreshProviderRanking()

		$scope.setProviderRankingUnit = (unit) ->
			$scope.provider_ranking.unit = unit
			$scope.refreshProviderRanking()

		$scope.providerQueryChange = ->
			if $scope.providersDetails[$scope.providerQuery.name]
				$scope.provider_ranking.name = $scope.providersDetails[$scope.providerQuery.name].provider
				$scope.refreshProviderRanking()


		#
		# Apps
		#
		$scope.appQuery = key:''
		$scope.app_ranking =
			name: 'facebook'
			key: ''
			target_names:
				'a:auth_array:[app]:p:[provider]':'Scopes auth'
				'a:auth_array:[app]:p:[provider]:success':'Scopes auth success'
				'a:auth_array:[app]:p:[provider]:error':'Scopes auth errors'
			target: 'a:auth_array:[app]:p:[provider]'
			unit: ''
		$scope.refreshAppRanking = ->
			opts = target:$scope.app_ranking.target.replace '[provider]', $scope.app_ranking.name
			opts.target = opts.target.replace '[app]', $scope.app_ranking.key
			opts.unit = $scope.app_ranking.unit if $scope.app_ranking.unit
			AdmService.getRanking opts, (success) ->
				$scope.appFiltered = success.data
				$scope.appPagination =
					nbPerPage: 15
					nbPages: Math.ceil($scope.appFiltered.length / 15)
					current: 1
					max: 5

		$scope.refreshAppRanking()

		$scope.setAppRankingTarget = (target) ->
			$scope.app_ranking.target = target
			$scope.refreshAppRanking()

		$scope.setAppRankingUnit = (unit) ->
			$scope.app_ranking.unit = unit
			$scope.refreshAppRanking()

		$scope.appQueryChange = ->
			$scope.app_ranking.key = $scope.appQuery.key
			$scope.refreshAppRanking()

		$scope.providerAppQueryChange = ->
			if $scope.providersDetails[$scope.providerAppQuery.name]
				$scope.app_ranking.name = $scope.providersDetails[$scope.providerAppQuery.name].provider
				$scope.refreshAppRanking()


		#
		# Wishlist
		#

		AdmService.getWishlist (success) ->
			$scope.wishListProviders = success.data
			$scope.wishListFiltered = $scope.wishListProviders

			$scope.wishListPagination =
				nbPerPage: 15
				nbPages: Math.ceil($scope.wishListProviders.length / 15)
				current: 1
				max: 5

		$scope.wishListQueryChange = (query)->

			$timeout (->
				$scope.wishListQuery = query
				$scope.wishListFiltered = $filter('filter')($scope.wishListProviders, query)
				$scope.wishListPagination.nbPages = Math.ceil($scope.wishListFiltered.length / $scope.wishLIstPagination.nbPerPage)
				$scope.wishListpagination.current = 1
			), 0

		$scope.removeProvider = (provider)->
			$scope.info = {}
			if confirm('Are you sure to remove this wish ?')
				AdmService.removeProvider provider.name, (success) ->

					index = $scope.wishListProviders.indexOf(provider)
					$scope.wishListProviders.splice(index, 1)
					$scope.wishListFiltered = $filter('filter')($scope.wishListProviders, $scope.wishListQuery)

					$scope.wishListPagination =
						nbPerPage: 15
						nbPages: Math.ceil($scope.wishListProviders.length / 15)
						current: 1
						max: 5

					$scope.info =
						status: true
						message : "#{success.data.name} has been deleted"

				, (error) ->
					$scope.info = error

		$scope.setProviderStatus = (provider, status)->
			$scope.info = {}
			if confirm('are you sure to change status to ' + status + ' ?')
				AdmService.setProviderStatus provider.name, status, (success) ->
					refreshProvidersList success.data
				, (error) ->
					$scope.info = error

		refreshProvidersList = (provider) ->
			for i of $scope.wishListProviders
				if $scope.wishListProviders[i].name == provider.name
					$scope.wishListProviders[i].status = provider.status

